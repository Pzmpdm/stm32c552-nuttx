// SPDX-License-Identifier: Apache-2.0
// Use the existing CFG1/CFG2 controller; observe accesses without supplying data
// or ready flags. The built-in FIFO is unbounded; counters check the driver's
// outstanding data against the C552's 16-byte hardware FIFO.
using Antmicro.Renode.Core;
using Antmicro.Renode.Peripherals.Bus;

namespace Antmicro.Renode.Peripherals.SPI
{
    public class STM32C5_SPI : STM32WBA_SPI, IBytePeripheral, IWordPeripheral, IDoubleWordPeripheral
    {
        public STM32C5_SPI(IMachine machine) : base(machine)
        {
        }

        public override void Reset()
        {
            base.Reset();
            enabled = false;
            pending = 0;
            softwareNss = 0;
            configuration1 = 0;
            configuration2 = 0;
            suppressReceive = false;
            ClearTrace();
        }

        // Withhold RXP so the driver's poll can time out. Dropping the
        // unread frames on release keeps the following transfer separate.
        // This is not an overrun or an SCK model.
        public bool SuppressReceive
        {
            get { return suppressReceive; }
            set
            {
                suppressReceive = value;
                if(value)
                {
                    return;
                }

                for(var i = 0; i < 64 && (base.ReadDoubleWord(0x14) & 1) != 0; i++)
                {
                    base.ReadDoubleWord(0x30);
                }
            }
        }

        public void ClearTrace()
        {
            MaxPending = 0;
            AccessErrors = 0;
            UnsafeConfigWrites = 0;
            ByteWrites = 0;
            WordWrites = 0;
            DoubleWordWrites = 0;
        }

        public new byte ReadByte(long offset)
        {
            ObserveRead(offset, 1);
            return base.ReadByte(offset);
        }

        public new ushort ReadWord(long offset)
        {
            ObserveRead(offset, 2);
            var result = base.ReadWord(offset);
            return offset == 0x30 && MsbFirst ? SwapWord(result) : result;
        }

        public new uint ReadDoubleWord(long offset)
        {
            ObserveRead(offset, 4);
            // Tagged model fields are write-only. Hardware retains CFG bits
            // for read-modify-write, so keep their complete readback here.
            if(offset == 0) return base.ReadDoubleWord(offset) | softwareNss;
            if(offset == 8) return configuration1;
            if(offset == 12) return configuration2;
            var result = base.ReadDoubleWord(offset);
            if(offset == 0x14 && suppressReceive)
            {
                result &= ~1u;
            }
            return offset == 0x30 && MsbFirst ? SwapDoubleWord(result) : result;
        }

        public new void WriteByte(long offset, byte value)
        {
            ObserveWrite(offset, value, 1);
            base.WriteByte(offset, value);
        }

        public new void WriteWord(long offset, ushort value)
        {
            ObserveWrite(offset, value, 2);
            base.WriteWord(offset, offset == 0x20 && MsbFirst ? SwapWord(value) : value);
        }

        public new void WriteDoubleWord(long offset, uint value)
        {
            ObserveWrite(offset, value, 4);
            base.WriteDoubleWord(offset, offset == 0x20 && MsbFirst ? SwapDoubleWord(value) : value);
        }

        private void ObserveRead(long offset, int width)
        {
            if(offset == 0x30)
            {
                if(pending < width)
                {
                    AccessErrors++;
                }
                pending -= width;
            }
        }

        private void ObserveWrite(long offset, uint value, int width)
        {
            if(offset == 0)
            {
                softwareNss = value & (1u << 12);
                enabled = (value & 1) != 0;
                if(!enabled)
                {
                    pending = 0;
                }
            }
            if((offset == 8 || offset == 12 || offset == 0x40) && enabled)
            {
                UnsafeConfigWrites++;
            }
            if(!enabled && offset == 8) configuration1 = value;
            if(!enabled && offset == 12) configuration2 = value;
            if(offset != 0x20)
            {
                return;
            }
            var bits = (int)(base.ReadDoubleWord(8) & 31) + 1;
            var expected = bits <= 8 ? 1 : bits <= 16 ? 2 : 4;
            if(width != expected)
            {
                AccessErrors++;
            }
            pending += width;
            MaxPending = System.Math.Max(MaxPending, pending);
            if(width == 1) ByteWrites++;
            if(width == 2) WordWrites++;
            if(width == 4) DoubleWordWrites++;
        }

        public int MaxPending { get; private set; }
        public int AccessErrors { get; private set; }
        public int UnsafeConfigWrites { get; private set; }
        public int ByteWrites { get; private set; }
        public int WordWrites { get; private set; }
        public int DoubleWordWrites { get; private set; }
        private bool suppressReceive;
        // Renode 1.17 streams wide frames in little endian byte order.
        // SPI MSB-first sends the high byte first; bridge both TX and RX.
        private bool MsbFirst => (configuration2 & (1u << 23)) == 0;
        private static ushort SwapWord(ushort value)
        {
            return (ushort)((value << 8) | (value >> 8));
        }
        private static uint SwapDoubleWord(uint value)
        {
            return (value << 24) | ((value & 0xFF00) << 8)
                | ((value >> 8) & 0xFF00) | (value >> 24);
        }

        private uint softwareNss;
        private uint configuration1;
        private uint configuration2;
        private bool enabled;
        private int pending;
    }
}
