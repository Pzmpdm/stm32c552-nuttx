// SPDX-License-Identifier: Apache-2.0
// Complete the software update event missing from Renode's STM32_Timer.
// All counting, compare events and GPIO output use the built-in model.
using Antmicro.Renode.Core;
using Antmicro.Renode.Peripherals.Bus;
using Antmicro.Renode.Peripherals.Timers;

namespace Antmicro.Renode.Peripherals.Timers
{
    [AllowedTranslations(AllowedTranslation.ByteToDoubleWord | AllowedTranslation.WordToDoubleWord)]
    public class STM32C5_TIM2 : STM32_Timer, IDoubleWordPeripheral
    {
        public STM32C5_TIM2(IMachine machine, ulong frequency)
            : base(machine, frequency, uint.MaxValue)
        {
        }

        public new void WriteDoubleWord(long offset, uint value)
        {
            base.WriteDoubleWord(offset, value);
            if(offset == EventGeneration && (value & UpdateGeneration) != 0
                && (ReadDoubleWord(Control1) & UpdateDisable) == 0)
            {
                // UG transfers the programmed ARR to the active counter
                // limit even when CR1.ARPE is set. The parent handles CNT.
                Limit = ReadDoubleWord(AutoReload);
            }
        }

        private const long Control1 = 0x00;
        private const long EventGeneration = 0x14;
        private const long AutoReload = 0x2C;
        private const uint UpdateGeneration = 1 << 0;
        private const uint UpdateDisable = 1 << 1;
    }
}
