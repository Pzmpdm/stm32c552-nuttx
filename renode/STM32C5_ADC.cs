// SPDX-License-Identifier: Apache-2.0
// Reuse Renode's sequencer, voltage sources, conversion and IRQ logic.
// Add the C5 power/calibration handshake and passive protocol observations.
using Antmicro.Renode.Core;
using Antmicro.Renode.Peripherals.Bus;

namespace Antmicro.Renode.Peripherals.Analog
{
    public class STM32C5_ADC : STM32_ADC_Common, IDoubleWordPeripheral
    {
        public STM32C5_ADC(IMachine machine, SystemBus sysbus, double referenceVoltage)
            : base(machine, referenceVoltage, 1, 0, null,
                   watchdogCount: 3, hasCalibration: true, channelCount: 14,
                   hasPrescaler: false, hasVbatPin: false,
                   hasChannelSequence: true, hasPowerRegister: false,
                   hasChannelSelect: false, hasOffset: false,
                   hasDifferentialMode: false, samplingTime: SamplingTime.PerChannel,
                   dualMode: false, hasLinearityCalibration: false,
                   hasChannelInjection: false, hasSeparateThresholdRegisters: true,
                   resolutionRange: ResolutionRange.Bits6_12,
                   hasChannelPreselection: true, hasScanDirection: false)
        {
            this.machine = machine;
            Reset();
            sysbus.AddWatchpointHook(0x44020C64, SysbusAccessWidth.DoubleWord,
                                    Access.Write, (cpu, address, width, value) =>
            {
                if((value & (1u << 10)) != 0)
                {
                    Reset();
                }
            });
        }

        public new void Reset()
        {
            base.Reset();
            power = DeepPowerDown;
            calibrating = false;
            calibrated = false;
            LastConfiguration = 0;
            LastSampleTime = 0;
            LastSequence = 0;
            LastPreselection = 0;
            Resets++;
        }

        public void ClearTrace()
        {
            Resets = 0;
            CalibrationStarts = 0;
            Calibrations = 0;
            Enables = 0;
            Starts = 0;
            DataReads = 0;
            SequencingErrors = 0;
        }

        public new uint ReadDoubleWord(long offset)
        {
            if(offset == Control)
            {
                UpdateCalibration();
                return (base.ReadDoubleWord(offset) & ~DeepPowerDown)
                    | power | (calibrating ? Calibrate : 0);
            }
            if(offset == 0)
            {
                var status = base.ReadDoubleWord(offset) & ~RegulatorReady;
                return IsRegulatorReady ? status | RegulatorReady : status;
            }
            if(offset == 0x40)
            {
                DataReads++;
            }
            return base.ReadDoubleWord(offset);
        }

        public new void WriteDoubleWord(long offset, uint value)
        {
            if(offset == Control)
            {
                UpdateCalibration();
                var wasRegulated = (power & Regulator) != 0;
                power = value & (Regulator | DeepPowerDown);
                if(!wasRegulated && (power & Regulator) != 0)
                {
                    regulatorSince = Now;
                }
                if((value & Calibrate) != 0 && !calibrating)
                {
                    CalibrationStarts++;
                    if(!IsRegulatorReady || (base.ReadDoubleWord(Control) & 1) != 0)
                    {
                        SequencingErrors++;
                    }
                    calibrating = true;
                    calibrated = false;
                    calibrationUntil = Now + 0.000008;
                }
                if((value & 1) != 0 && (base.ReadDoubleWord(Control) & 1) == 0)
                {
                    Enables++;
                    if(!calibrated || Now - calibrationUntil < 4.0 / 12000000)
                    {
                        SequencingErrors++;
                    }
                    if(StallReady)
                    {
                        value &= ~1u;
                    }
                }
                if((value & 4) != 0)
                {
                    Starts++;
                    if((base.ReadDoubleWord(Control) & 1) == 0 || !calibrated
                        || LastPreselection != 0x100 || LastSequence != 0x200)
                    {
                        SequencingErrors++;
                    }
                }
                value &= ~(Calibrate | DeepPowerDown);
            }
            if(offset == 0x0C) LastConfiguration = value;
            if(offset == 0x14) LastSampleTime = value;
            if(offset == 0x1C) LastPreselection = value;
            if(offset == 0x30) LastSequence = value;
            base.WriteDoubleWord(offset, value);
        }

        private void UpdateCalibration()
        {
            if(calibrating && !StallCalibration && Now >= calibrationUntil)
            {
                calibrating = false;
                calibrated = true;
                Calibrations++;
            }
        }

        public bool StallRegulator { get; set; }
        public bool StallCalibration { get; set; }
        public bool StallReady { get; set; }
        public int Resets { get; private set; }
        public int CalibrationStarts { get; private set; }
        public int Calibrations { get; private set; }
        public int Enables { get; private set; }
        public int Starts { get; private set; }
        public int DataReads { get; private set; }
        public int SequencingErrors { get; private set; }
        public uint LastConfiguration { get; private set; }
        public uint LastSampleTime { get; private set; }
        public uint LastPreselection { get; private set; }
        public uint LastSequence { get; private set; }

        private bool IsRegulatorReady => (power & (Regulator | DeepPowerDown)) == Regulator
            && !StallRegulator && Now >= regulatorSince + 0.000010;
        private double Now => machine.LocalTimeSource.ElapsedVirtualTime.TotalSeconds;
        private readonly IMachine machine;
        private uint power;
        private bool calibrating;
        private bool calibrated;
        private double regulatorSince;
        private double calibrationUntil;
        private const long Control = 8;
        private const uint RegulatorReady = 1u << 12;
        private const uint Regulator = 1u << 28;
        private const uint DeepPowerDown = 1u << 29;
        private const uint Calibrate = 1u << 31;
    }
}
