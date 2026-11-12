// SPDX-License-Identifier: Apache-2.0
// C552 single-block LPDMA. Transfer actual bus data and implement per-beat
// hardware requests, byte counts and W1C interrupt flags.
using System.Collections.Generic;
using Antmicro.Renode.Core;
using Antmicro.Renode.Peripherals.Bus;

namespace Antmicro.Renode.Peripherals.DMA
{
    public class STM32C5_LPDMA : IDoubleWordPeripheral, IKnownSize, INumberedGPIOOutput, IDMA
    {
        public STM32C5_LPDMA(SystemBus sysbus, int channelCount)
        {
            this.sysbus = sysbus;
            channels = new Channel[channelCount];
            var connections = new Dictionary<int, IGPIO>();
            for(var i = 0; i < channelCount; i++)
            {
                channels[i] = new Channel();
                connections[i] = channels[i].IRQ;
            }
            Connections = connections;
        }

        public void Reset()
        {
            foreach(var channel in channels)
            {
                ResetChannel(channel);
            }
            FailNext = false;
            StallNext = false;
            SoftwareStarts = 0;
            PeripheralBeats = 0;
            Completions = 0;
            Errors = 0;
            Suspensions = 0;
        }

        public uint ReadDoubleWord(long offset)
        {
            if(offset == 0x0C)
            {
                uint pending = 0;
                for(var i = 0; i < channels.Length; i++)
                {
                    if((channels[i].Status & channels[i].Control & FlagMask) != 0)
                    {
                        pending |= 1u << i;
                    }
                }
                return pending;
            }
            var channel = ChannelAt(ref offset);
            if(channel == null)
            {
                return 0;
            }
            switch(offset)
            {
                case 0x10: return channel.Status | ((channel.Control & Enable) == 0 ? 1u : 0u);
                case 0x14: return channel.Control;
                case 0x40: return channel.Transfer1;
                case 0x44: return channel.Transfer2;
                case 0x48: return channel.Remaining;
                case 0x4C: return channel.Source;
                case 0x50: return channel.Destination;
                case 0x7C: return channel.Link;
                default: return 0;
            }
        }

        public void WriteDoubleWord(long offset, uint value)
        {
            var channel = ChannelAt(ref offset);
            if(channel == null)
            {
                return;
            }
            if(offset == 0x0C)
            {
                channel.Status &= ~(value & FlagMask);
                UpdateInterrupt(channel);
                return;
            }
            if(offset == 0x14)
            {
                WriteControl(channel, value);
                return;
            }
            if((channel.Control & Enable) != 0)
            {
                Finish(channel, UserError);
                return;
            }
            switch(offset)
            {
                case 0x40: channel.Transfer1 = value; break;
                case 0x44: channel.Transfer2 = value; break;
                case 0x48: channel.Remaining = value & 0xFFFF; break;
                case 0x4C: channel.Source = value; break;
                case 0x50: channel.Destination = value; break;
                case 0x7C: channel.Link = value; break;
            }
        }

        public void RequestTransfer(int endpoint)
        {
            // Renode ADC uses a one-based endpoint. Endpoint 1 maps to
            // C552 request signal 0 (ADC1), independently of the channel.
            var request = (uint)(endpoint - 1);
            foreach(var channel in channels)
            {
                if((channel.Control & (Enable | Suspend)) == Enable &&
                   channel.Transfer2 == request && !channel.Stalled)
                {
                    if(TransferBeat(channel))
                    {
                        PeripheralBeats++;
                    }
                }
            }
        }

        private Channel ChannelAt(ref long offset)
        {
            if(offset < 0x50)
            {
                return null;
            }
            var relative = offset - 0x50;
            var number = relative / 0x80;
            offset = relative % 0x80;
            return number < channels.Length ? channels[number] : null;
        }

        private void WriteControl(Channel channel, uint value)
        {
            if((value & ResetCommand) != 0)
            {
                ResetChannel(channel);
                return;
            }
            var enabled = (channel.Control & Enable) != 0;
            channel.Control = (value & (FlagMask | Suspend)) | (enabled ? Enable : 0);
            if(enabled && (value & Suspend) != 0)
            {
                channel.Status |= Suspended;
                Suspensions++;
            }
            if(!enabled && (value & Enable) != 0)
            {
                channel.Control |= Enable;
                var sourceWidth = channel.Transfer1 & 3;
                var destinationWidth = (channel.Transfer1 >> 16) & 3;
                channel.Width = 1u << (int)sourceWidth;
                if(sourceWidth > 2 || sourceWidth != destinationWidth ||
                   channel.Remaining == 0 || channel.Link != 0 ||
                   ((channel.Source | channel.Destination | channel.Remaining) & (channel.Width - 1)) != 0 ||
                   (channel.Transfer1 & ~0x000B000Bu) != 0 ||
                   (channel.Transfer2 & ~(0x7Fu | SoftwareRequest)) != 0)
                {
                    Finish(channel, UserError);
                    return;
                }
                channel.Stalled = StallNext;
                StallNext = false;
                if((channel.Transfer2 & SoftwareRequest) != 0)
                {
                    SoftwareStarts++;
                    while((channel.Control & Enable) != 0 && !channel.Stalled)
                    {
                        TransferBeat(channel);
                    }
                }
            }
            UpdateInterrupt(channel);
        }

        private bool TransferBeat(Channel channel)
        {
            if(FailNext)
            {
                FailNext = false;
                Finish(channel, DataError);
                return false;
            }
            switch(channel.Width)
            {
                case 1: sysbus.WriteByte(channel.Destination, sysbus.ReadByte(channel.Source)); break;
                case 2: sysbus.WriteWord(channel.Destination, sysbus.ReadWord(channel.Source)); break;
                default: sysbus.WriteDoubleWord(channel.Destination, sysbus.ReadDoubleWord(channel.Source)); break;
            }
            if((channel.Transfer1 & (1u << 3)) != 0) channel.Source += channel.Width;
            if((channel.Transfer1 & (1u << 19)) != 0) channel.Destination += channel.Width;
            channel.Remaining -= channel.Width;
            if(channel.Remaining == 0)
            {
                Finish(channel, Complete);
            }
            return true;
        }

        private void Finish(Channel channel, uint flag)
        {
            channel.Control &= ~Enable;
            channel.Status |= flag;
            if(flag == Complete) Completions++;
            else Errors++;
            UpdateInterrupt(channel);
        }

        private static void UpdateInterrupt(Channel channel)
        {
            channel.IRQ.Set((channel.Control & channel.Status & FlagMask) != 0);
        }

        private static void ResetChannel(Channel channel)
        {
            channel.Control = 0;
            channel.Status = 0;
            channel.Transfer1 = 0;
            channel.Transfer2 = 0;
            channel.Remaining = 0;
            channel.Source = 0;
            channel.Destination = 0;
            channel.Link = 0;
            channel.Stalled = false;
            UpdateInterrupt(channel);
        }

        public long Size => 0x1000;
        public int NumberOfChannels => channels.Length;
        public IReadOnlyDictionary<int, IGPIO> Connections { get; }
        public bool FailNext { get; set; }
        public bool StallNext { get; set; }
        public int SoftwareStarts { get; private set; }
        public int PeripheralBeats { get; private set; }
        public int Completions { get; private set; }
        public int Errors { get; private set; }
        public int Suspensions { get; private set; }
        private readonly SystemBus sysbus;
        private readonly Channel[] channels;
        private const uint Enable = 1;
        private const uint ResetCommand = 2;
        private const uint Suspend = 4;
        private const uint Complete = 1 << 8;
        private const uint DataError = 1 << 10;
        private const uint UserError = 1 << 12;
        private const uint Suspended = 1 << 13;
        private const uint FlagMask = 0x7F00;
        private const uint SoftwareRequest = 1 << 9;

        private class Channel
        {
            public readonly GPIO IRQ = new GPIO();
            public uint Control;
            public uint Status;
            public uint Transfer1;
            public uint Transfer2;
            public uint Remaining;
            public uint Source;
            public uint Destination;
            public uint Width;
            public uint Link;
            public bool Stalled;
        }
    }
}
