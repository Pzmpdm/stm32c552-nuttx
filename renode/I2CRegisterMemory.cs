// SPDX-License-Identifier: Apache-2.0
// Test fixture with an 8-bit register pointer and persistent writable bytes.
using Antmicro.Renode.Peripherals.I2C;

namespace Antmicro.Renode.Peripherals.I2C
{
    public class I2CRegisterMemory : II2CPeripheral
    {
        public I2CRegisterMemory()
        {
            Reset();
        }

        public void Reset()
        {
            for(var i = 0; i < memory.Length; i++)
            {
                memory[i] = (byte)((i * 37 + 11) & 0xFF);
            }
            pointer = 0;
            continuingWrite = false;
            WrittenBytes = 0;
            ReadBytes = 0;
            Stops = 0;
            ClearTrace();
            LastTiming = 0;
            PeripheralEnabled = false;
            AnalogDisableWritten = false;
            OpenDrainWritten = 0;
        }

        public void Write(byte[] data)
        {
            var index = 0;
            if(!continuingWrite && data.Length > 0)
            {
                pointer = data[index++];
                continuingWrite = true;
            }
            for(; index < data.Length; index++)
            {
                memory[pointer] = data[index];
                pointer = (pointer + 1) & 0xFF;
                WrittenBytes++;
            }
        }

        public byte[] Read(int count = 1)
        {
            var result = new byte[count];
            for(var i = 0; i < count; i++)
            {
                result[i] = memory[pointer];
                pointer = (pointer + 1) & 0xFF;
            }
            ReadBytes += count;
            return result;
        }

        public void FinishTransmission()
        {
            continuingWrite = false;
            Stops++;
        }

        public byte GetByte(int index)
        {
            return memory[index & 0xFF];
        }

        public void ClearTrace()
        {
            Starts = 0;
            StopRequests = 0;
            ReloadWrites = 0;
            TimingWhileEnabled = 0;
        }

        public void ObserveControl(uint value)
        {
            if((value & (1u << 13)) != 0) Starts++;
            if((value & (1u << 14)) != 0) StopRequests++;
            if((value & (1u << 24)) != 0) ReloadWrites++;
        }

        public void ObserveConfig(uint value)
        {
            PeripheralEnabled = (value & 1) != 0;
            AnalogDisableWritten |= (value & (1u << 12)) != 0;
        }

        public void ObserveTiming(uint value)
        {
            LastTiming = value;
            if(PeripheralEnabled) TimingWhileEnabled++;
        }

        public void ObserveOutputType(uint value)
        {
            OpenDrainWritten |= value & 0x300;
        }

        public int WrittenBytes { get; private set; }
        public int ReadBytes { get; private set; }
        public int Stops { get; private set; }
        public int Starts { get; private set; }
        public int StopRequests { get; private set; }
        public int ReloadWrites { get; private set; }
        public int TimingWhileEnabled { get; private set; }
        public uint LastTiming { get; private set; }
        public bool PeripheralEnabled { get; private set; }
        public bool AnalogDisableWritten { get; private set; }
        public uint OpenDrainWritten { get; private set; }

        private readonly byte[] memory = new byte[256];
        private int pointer;
        private bool continuingWrite;
    }
}
