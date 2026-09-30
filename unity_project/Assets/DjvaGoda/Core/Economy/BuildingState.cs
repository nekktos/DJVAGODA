// Правила одной постройки: стройка, прочность и ступени, поле, урон
// (перенос building.gd — без вида, физики и сети; их даёт Unity-слой).
using System;

namespace DjvaGoda.Core
{
    public class BuildingState
    {
        public readonly BuildingKind Kind;
        public Faction Side;
        public float Progress;
        public int Grade;
        public float Health;
        /// Что выросло на поле и ещё не унесено. У прочих построек пусто.
        public int[] Grown = Res.Empty();
        float _grain;

        public BuildingState(BuildingKind kind, Faction side, bool prebuilt)
        {
            Kind = kind;
            Side = side;
            Progress = prebuilt ? 1f : 0f;
            Health = MaxHealth;
        }

        public bool Done { get { return Progress >= 1f; } }

        public float MaxHealth { get { return Res.BuildingHealth(Kind, Grade); } }

        /// Стройка идёт и без батраков (иначе первая партия встала бы намертво):
        /// базовая единица — сам хозяин; каждый строитель прибавляет ещё одну.
        public void Build(float delta, int builders)
        {
            if (Done) return;
            float rate = 1f + Math.Max(0, builders);
            Progress = Math.Min(1f, Progress + delta * rate / Res.BuildTime(Kind));
        }

        /// Поле растит само; фермер уносит (добытое засчитывается, когда донесено).
        public void Grow(float delta)
        {
            if (Kind != BuildingKind.Farm || !Done) return;
            _grain += Res.FarmRate * delta;
            int whole = (int)_grain;
            if (whole <= 0) return;
            _grain -= whole;
            int food = (int)ResourceKind.Food;
            Grown[food] = Math.Min(Res.FarmCap, Grown[food] + whole);
        }

        public int[] TakeGrown(int limit)
        {
            var taken = Res.Empty();
            if (Kind != BuildingKind.Farm) return taken;
            int food = (int)ResourceKind.Food;
            int amount = Math.Min(limit, Grown[food]);
            Grown[food] -= amount;
            taken[food] = amount;
            return taken;
        }

        /// Цена следующей ступени; пусто — крепче некуда или недостроено.
        public int[] UpgradeCost()
        {
            if (!Done) return new int[0];
            return Res.GradeCost(Kind, Grade);
        }

        /// Поднять ступень. Прибавка прочности — разница ступеней: побитая стена
        /// остаётся побитой, но крепче на столько же. Цену списывает укрепляющий.
        public bool ApplyUpgrade()
        {
            if (UpgradeCost().Length == 0) return false;
            float before = MaxHealth;
            Grade += 1;
            Health = Math.Min(MaxHealth, Health + MaxHealth - before);
            return true;
        }

        /// Удар по постройке. Возвращает снятое; ноль прочности — разрушена.
        /// Стража ломает постройки злодея по своей снаряжённости (ответ автора).
        public float TakeDamage(float amount, int sourceFaction, int gearTier, int armorTier)
        {
            if (Health <= 0f) return 0f;
            float dealt = amount * Factions.VillainHitScale(Side, sourceFaction, gearTier, armorTier);
            float before = Health;
            Health = Math.Max(0f, Health - dealt);
            return before - Health;
        }

        public bool Destroyed { get { return Health <= 0f; } }
    }
}
