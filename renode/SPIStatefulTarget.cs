// SPDX-License-Identifier: Apache-2.0
// A byte-stream target whose response depends on MOSI and prior bytes in CS.
using System.Collections.Generic;
using System.Linq;
using Antmicro.Renode.Core;
using Antmicro.Renode.Peripherals;
using Antmicro.Renode.Peripherals.SPI;

namespace Antmicro.Renode.Peripherals.SPI
{
    public class SPIStatefulTarget : ISPIPeripheral, IGPIOReceiver
    {
        public SPIStatefulTarget()
        {
            Reset();
        }

        public void Reset()
        {
            selected = false;
            previous = 0x3C;
            ClearTrace();
        }

        public void ClearTrace()
        {
            Selects = 0;
            Deselects = 0;
            SuspendNotifications = 0;
            UnselectedBytes = 0;
            bytes.Clear();
        }

        public void OnGPIO(int number, bool value)
        {
            var active = !value;
            if(active == selected)
            {
                return;
            }
            selected = active;
            if(active)
            {
                Selects++;
                previous = 0x3C;
            }
            else
            {
                Deselects++;
            }
        }

        public byte Transmit(byte value)
        {
            if(!selected)
            {
                UnselectedBytes++;
                return 0xFF;
            }
            bytes.Add(value);
            var result = (byte)(value ^ previous ^ 0xA5);
            previous = value;
            return result;
        }

        // A peripheral suspension does not release the board's GPIO CS.
        public void FinishTransmission()
        {
            SuspendNotifications++;
        }

        public string Bytes => string.Join("", bytes.Select(x => x.ToString("X2")));
        public int Selects { get; private set; }
        public int Deselects { get; private set; }
        public int SuspendNotifications { get; private set; }
        public int UnselectedBytes { get; private set; }
        private bool selected;
        private byte previous;
        private readonly List<byte> bytes = new List<byte>();
    }
}
