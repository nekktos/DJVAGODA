// Казна стороны: запас «при себе» и склад (перенос stockpile.gd и wallet.gd).
//
// Считает ТОЛЬКО хост — эту проверку делает Unity-слой, ядро о сети не знает.
// Здесь — сами правила: потолок на каждый ресурс, трата сперва из того, что
// при себе, склад как страховка от смерти.
using System;

namespace DjvaGoda.Core
{
    /// Один запас с потолком на каждый ресурс.
    public class Stockpile : IStock
    {
        public int[] Amounts = Res.Empty();
        public int Capacity = Res.BaseCapacity;

        public event Action Changed;

        public int GetAmount(ResourceKind kind) { return GetAmount((int)kind); }

        public int GetAmount(int kind)
        {
            if (kind < 0 || kind >= Amounts.Length) return 0;
            return Amounts[kind];
        }

        public bool CanAfford(int[] cost)
        {
            for (int i = 0; i < Res.Count; i++)
                if (GetAmount(i) < Res.At(cost, i)) return false;
            return true;
        }

        public bool Spend(int[] cost)
        {
            if (!CanAfford(cost)) return false;
            for (int i = 0; i < Res.Count; i++) Amounts[i] -= Res.At(cost, i);
            Notify();
            return true;
        }

        /// Положить сколько влезет под потолок; вернуть положенное.
        public int Add(int kind, int value)
        {
            if (kind < 0 || kind >= Res.Count || value <= 0) return 0;
            int room = Math.Max(0, Capacity - Amounts[kind]);
            int taken = Math.Min(room, value);
            Amounts[kind] += taken;
            Notify();
            return taken;
        }

        public int Take(int kind, int value)
        {
            if (kind < 0 || kind >= Res.Count || value <= 0) return 0;
            int taken = Math.Min(Amounts[kind], value);
            Amounts[kind] -= taken;
            Notify();
            return taken;
        }

        public void RaiseCapacity(int bonus)
        {
            Capacity += bonus;
            Notify();
        }

        public int Total()
        {
            int sum = 0;
            for (int i = 0; i < Res.Count; i++) sum += Amounts[i];
            return sum;
        }

        void Notify()
        {
            var handler = Changed;
            if (handler != null) handler();
        }
    }

    /// Казна стороны: «при себе» падает со смертью, «в складе» переживает её.
    public class Wallet : IStock
    {
        public readonly Stockpile Carried = new Stockpile();
        public readonly Stockpile Stored = new Stockpile { Capacity = 0 };
        public int Horses;
        public int HorsesOut;

        public int HorsesFree { get { return Math.Max(0, Horses - HorsesOut); } }

        public int GetAmount(ResourceKind kind) { return GetAmount((int)kind); }

        public int GetAmount(int kind)
        {
            return Carried.GetAmount(kind) + Stored.GetAmount(kind);
        }

        public bool CanAfford(int[] cost)
        {
            for (int i = 0; i < Res.Count; i++)
                if (GetAmount(i) < Res.At(cost, i)) return false;
            return true;
        }

        /// Платим сперва тем, что при себе, остаток — со склада.
        public bool Spend(int[] cost)
        {
            if (!CanAfford(cost)) return false;
            for (int i = 0; i < Res.Count; i++)
            {
                int left = Res.At(cost, i);
                if (left <= 0) continue;
                int fromHand = Math.Min(left, Carried.GetAmount(i));
                if (fromHand > 0)
                {
                    Carried.Take(i, fromHand);
                    left -= fromHand;
                }
                if (left > 0) Stored.Take(i, left);
            }
            return true;
        }

        public int Add(int kind, int value) { return Carried.Add(kind, value); }
        public int AddStored(int kind, int value) { return Stored.Add(kind, value); }

        /// Сдать всё, что при себе, в склад — сколько влезет.
        public int Deposit()
        {
            int moved = 0;
            for (int i = 0; i < Res.Count; i++)
            {
                int have = Carried.GetAmount(i);
                if (have <= 0) continue;
                int placed = Stored.Add(i, have);
                if (placed > 0)
                {
                    Carried.Take(i, placed);
                    moved += placed;
                }
            }
            return moved;
        }

        /// Смерть: всё, что при себе, падает кучей. Возвращает выпавшее.
        public int[] DropCarried()
        {
            var lost = (int[])Carried.Amounts.Clone();
            Carried.Amounts = Res.Empty();
            return lost;
        }

        public void RaiseCapacity(int bonus) { Stored.RaiseCapacity(bonus); }

        public int CarriedTotal() { return Carried.Total(); }

        /// Выдать ресурсы (старт стороны, проверки): при себе, с потолком не меньше выданного.
        public void Grant(int[] values)
        {
            int biggest = 0;
            for (int i = 0; i < Res.Count; i++) biggest = Math.Max(biggest, Res.At(values, i));
            Carried.Capacity = Math.Max(Carried.Capacity, biggest);
            Carried.Amounts = Res.Fit(values);
        }
    }
}
