// SPDX-License-Identifier: Apache-2.0
// Each reload key replaces the pending timeout. A callback from the previous
// deadline is ignored. 32 kHz is nominal. There is no reset-reason flag.
using System;
using Antmicro.Renode.Core;
using Antmicro.Renode.Peripherals.Bus;
using Antmicro.Renode.Time;

namespace Antmicro.Renode.Peripherals.Timers
{
    public class STM32C5_IWDG : IDoubleWordPeripheral, IWordPeripheral, IBytePeripheral, IKnownSize
    {
        public STM32C5_IWDG(IMachine machine, ulong frequency = 32000)
        {
            this.machine = machine;
            this.frequency = frequency;
            reload = 0xFFF;
        }

        public long Size => 0x400;
        public int Kicks { get; private set; }
        public int Resets { get; private set; }

        public void Reset()
        {
            started = false;
            unlocked = false;
            reload = 0xFFF;
            Cancel();
        }

        public uint ReadDoubleWord(long offset) => 0;
        public ushort ReadWord(long offset) => 0;
        public byte ReadByte(long offset) => 0;

        public void WriteDoubleWord(long offset, uint value) => Write(offset, value);
        public void WriteWord(long offset, ushort value) => Write(offset, value);
        public void WriteByte(long offset, byte value) => Write(offset, value);

        private void Write(long offset, uint value)
        {
            if(offset == 0)
            {
                unlocked = false;
                if(value == 0x5555)
                {
                    unlocked = true;
                }
                else if(value == 0xAAAA)
                {
                    Kicks++;
                    Rearm();
                }
                else if(value == 0xCCCC)
                {
                    started = true;
                    Rearm();
                }
            }
            else if(offset == 8 && unlocked)
            {
                reload = value & 0xFFF;
                if(reload == 0)
                {
                    reload = 1;
                }
            }
        }

        private void Cancel()
        {
            epoch++;
            if(callback != null)
            {
                machine.ClockSource.TryRemoveClockEntry(callback);
                callback = null;
            }
        }

        private void Rearm()
        {
            Cancel();
            if(!started)
            {
                return;
            }

            var seen = epoch;
            callback = () =>
            {
                if(seen != epoch || !started)
                {
                    return;
                }

                started = false;
                callback = null;
                Resets++;
                machine.RequestReset();
            };
            machine.ClockSource.AddClockEntry(new ClockEntry(TimeoutTicks, frequency,
                callback, this, "iwdg", true, Direction.Descending));
        }

        // Prescaler /256. At the nominal 32 kHz, a reload of 0x100 is about two seconds.
        private ulong TimeoutTicks => (ulong)reload * 256;

        private readonly IMachine machine;
        private readonly ulong frequency;
        private Action callback;
        private uint reload;
        private int epoch;
        private bool unlocked;
        private bool started;
    }
}
