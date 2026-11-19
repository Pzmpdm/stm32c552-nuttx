// SPDX-License-Identifier: Apache-2.0
// Register-level USB device. Packet bytes live in the 2 KiB buffer and are
// what the CPU reads back. An injected OUT raises CTR first; the count and
// bytes land 500 ns later (ES0661). This is not a PHY, chirp, or VBUS model.
using System;
using System.Collections.Generic;
using Antmicro.Renode.Core;
using Antmicro.Renode.Peripherals;
using Antmicro.Renode.Peripherals.Bus;

namespace Antmicro.Renode.Peripherals.USB
{
    public class STM32C5_USB : IDoubleWordPeripheral, IWordPeripheral, IBytePeripheral, IKnownSize
    {
        public STM32C5_USB(IMachine machine)
        {
            this.machine = machine;
            IRQ = new GPIO();
            Ram = new byte[0x800];
            epr = new ushort[8];
            Reset();
        }

        public GPIO IRQ { get; }
        public long Size => 0x60;
        public bool InjectEarlyCtr { get; set; }
        public int EarlyReads { get; private set; }
        public int DelayedPackets { get; private set; }
        public byte[] Ram { get; }

        public void Reset()
        {
            Array.Clear(epr, 0, epr.Length);
            Array.Clear(Ram, 0, Ram.Length);
            cntr = 0;
            istr = 0;
            daddr = 0;
            bcdr = 0;
            pending = null;
            EarlyReads = 0;
            DelayedPackets = 0;
            IRQ.Unset();
        }

        public void BusReset()
        {
            CommitIfDue();
            istr = (ushort)(istr | (1 << 10));
            UpdateIrq();
        }

        public void Setup(string hex)
        {
            CommitIfDue();
            var data = Parse(hex);
            WriteBuffer(RxAddress(0), data);
            SetRxCount(0, data.Length);
            epr[0] = (ushort)((epr[0] & ~((3 << 12) | (3 << 4) | (1 << 7))) | (2 << 12) | (2 << 4) | (1 << 15) | (1 << 11));
            istr = (ushort)((istr & ~0x1f) | (1 << 15) | (1 << 4));
            UpdateIrq();
        }

        public void BulkOut(int ep, string hex)
        {
            CommitIfDue();
            var data = Parse(hex);
            if(InjectEarlyCtr)
            {
                pending = data;
                pendingEp = ep;
                pendingAtMs = machine.LocalTimeSource.ElapsedVirtualTime.TotalMilliseconds;
                DelayedPackets++;
            }
            else
            {
                WriteBuffer(RxAddress(ep), data);
                SetRxCount(ep, data.Length);
            }

            RaiseRx(ep);
        }

        public void StatusOut(int ep)
        {
            CommitIfDue();
            SetRxCount(ep, 0);
            RaiseRx(ep);
        }

        public void CompleteIn(int ep)
        {
            CommitIfDue();
            epr[ep] = (ushort)((epr[ep] & ~(3 << 4)) | (2 << 4) | (1 << 7));
            istr = (ushort)((istr & ~0x1f) | (1 << 15) | ep);
            UpdateIrq();
        }

        public string TxHex(int ep)
        {
            CommitIfDue();
            var addr = ReadRam16(ep * 8);
            var count = ReadRam16(ep * 8 + 2);
            var chars = new char[count * 2];
            for(var i = 0; i < count; i++)
            {
                var b = addr + i < Ram.Length ? Ram[addr + i] : (byte)0;
                chars[i * 2] = Hex(b >> 4);
                chars[i * 2 + 1] = Hex(b & 0xf);
            }

            return new string(chars);
        }

        public uint ReadDoubleWord(long offset) => Read16(offset);
        public ushort ReadWord(long offset) => (ushort)Read16(offset);
        public byte ReadByte(long offset) => (byte)Read16(offset);

        public void WriteDoubleWord(long offset, uint value) => Write16(offset, (ushort)value);
        public void WriteWord(long offset, ushort value) => Write16(offset, value);
        public void WriteByte(long offset, byte value) => Write16(offset, value);

        public byte ReadRam(long offset)
        {
            CommitIfDue();
            if(pending != null && HitsPending(offset, 1))
            {
                EarlyReads++;
            }

            return offset >= 0 && offset < Ram.Length ? Ram[offset] : (byte)0;
        }

        public void WriteRam(long offset, byte value)
        {
            if(offset >= 0 && offset < Ram.Length)
            {
                Ram[offset] = value;
            }
        }

        private void Write16(long offset, ushort value)
        {
            if(offset >= 0 && offset < 0x20)
            {
                WriteEpr((int)(offset >> 2), value);
                return;
            }

            if(offset == 0x40)
            {
                cntr = value;
                UpdateIrq();
                return;
            }

            if(offset == 0x44)
            {
                istr &= value;
                UpdateIrq();
                return;
            }

            if(offset == 0x4c)
            {
                daddr = value;
                return;
            }

            if(offset == 0x58)
            {
                bcdr = value;
            }
        }

        private uint Read16(long offset)
        {
            CommitIfDue();
            if(offset >= 0 && offset < 0x20)
            {
                return epr[offset >> 2];
            }

            if(offset == 0x40) return cntr;
            if(offset == 0x44) return istr;
            if(offset == 0x4c) return daddr;
            if(offset == 0x58) return bcdr;
            return 0;
        }

        private void WriteEpr(int ep, ushort value)
        {
            var old = epr[ep];
            var neu = (ushort)(value & 0x070f);
            neu |= (ushort)((old ^ value) & 0x7070);
            if((value & (1 << 7)) != 0) neu |= (ushort)(old & (1 << 7));
            if((value & (1 << 15)) != 0)
            {
                neu |= (ushort)(old & ((1 << 15) | (1 << 11)));
            }

            epr[ep] = neu;
        }

        private void RaiseRx(int ep)
        {
            epr[ep] = (ushort)((epr[ep] & ~(3 << 12)) | (2 << 12) | (1 << 15));
            istr = (ushort)((istr & ~0x1f) | (1 << 15) | (1 << 4) | ep);
            UpdateIrq();
        }

        private void CommitIfDue()
        {
            if(pending == null)
            {
                return;
            }

            var elapsed = machine.LocalTimeSource.ElapsedVirtualTime.TotalMilliseconds - pendingAtMs;
            if(elapsed < 0.0005)
            {
                return;
            }

            WriteBuffer(RxAddress(pendingEp), pending);
            SetRxCount(pendingEp, pending.Length);
            pending = null;
        }

        private bool HitsPending(long offset, int width)
        {
            var desc = pendingEp * 8 + 4;
            if(offset < desc + 4 && offset + width > desc)
            {
                return true;
            }

            var addr = RxAddress(pendingEp);
            return offset < addr + pending.Length && offset + width > addr;
        }

        private int RxAddress(int ep) => ReadRam16(ep * 8 + 4);

        private int ReadRam16(int offset)
        {
            if(offset < 0 || offset + 1 >= Ram.Length)
            {
                return 0;
            }

            return Ram[offset] | (Ram[offset + 1] << 8);
        }

        private void SetRxCount(int ep, int count)
        {
            var at = ep * 8 + 6;
            Ram[at] = (byte)count;
            Ram[at + 1] = (byte)(count >> 8);
        }

        private void WriteBuffer(int address, IList<byte> data)
        {
            for(var i = 0; i < data.Count && address + i < Ram.Length; i++)
            {
                Ram[address + i] = data[i];
            }
        }

        private void UpdateIrq()
        {
            var pendingIrq = (istr & cntr & 0xff80) != 0;
            if(pendingIrq) IRQ.Set();
            else IRQ.Unset();
        }

        private static byte[] Parse(string hex)
        {
            var data = new byte[hex.Length / 2];
            for(var i = 0; i < data.Length; i++)
            {
                data[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
            }

            return data;
        }

        private static char Hex(int nibble) => (char)(nibble < 10 ? '0' + nibble : 'A' + nibble - 10);

        private readonly IMachine machine;
        private readonly ushort[] epr;
        private ushort cntr;
        private ushort istr;
        private ushort daddr;
        private ushort bcdr;
        private byte[] pending;
        private int pendingEp;
        private double pendingAtMs;
    }

    public class STM32C5_USBRam : IDoubleWordPeripheral, IWordPeripheral, IBytePeripheral, IKnownSize
    {
        public STM32C5_USBRam(STM32C5_USB usb)
        {
            this.usb = usb;
        }

        public long Size => 0x800;
        public void Reset() => usb.Reset();

        public byte ReadByte(long offset) => usb.ReadRam(offset);
        public ushort ReadWord(long offset)
        {
            return (ushort)(usb.ReadRam(offset) | (usb.ReadRam(offset + 1) << 8));
        }

        public uint ReadDoubleWord(long offset)
        {
            return (uint)(ReadWord(offset) | (ReadWord(offset + 2) << 16));
        }

        public void WriteByte(long offset, byte value) => usb.WriteRam(offset, value);
        public void WriteWord(long offset, ushort value)
        {
            usb.WriteRam(offset, (byte)value);
            usb.WriteRam(offset + 1, (byte)(value >> 8));
        }

        public void WriteDoubleWord(long offset, uint value)
        {
            WriteWord(offset, (ushort)value);
            WriteWord(offset + 2, (ushort)(value >> 16));
        }

        private readonly STM32C5_USB usb;
    }
}
