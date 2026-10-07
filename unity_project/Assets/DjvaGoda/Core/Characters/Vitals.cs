// Персонаж: здоровье, выносливость, мана, прокачка за опыт, движение
// (перенос health.gd, progression.gd и правил движения из player.gd).
//
// Здоровье и ману считает хост; выносливость — владелец, как и всё движение
// (модель прав Godot-версии: клиент считает своё движение сам).
using System;

namespace DjvaGoda.Core
{
    public enum Stat { Health, Stamina, Speed, Mana }

    public static class Movement
    {
        public const float Speed = 6f;
        /// Бегом — 10.5 м/с: карта полтора километра, пешком до дворца две минуты.
        public const float RunScale = 1.75f;
        public const float JumpVelocity = 5.5f;
        public const float DashSpeed = 22f;
        public const float DashTime = 0.18f;
        public const float DashCooldown = 1.2f;
        public const float DashStamina = 18f;
        public const float AimRange = 300f;
    }

    /// Прокачка за опыт: четыре шкалы по пять уровней, прибавкой поверх базы.
    public static class Progression
    {
        public static readonly string[] Names = { "здоровье", "выносливость", "бег", "мана" };
        public const float StepHealth = 15f;
        public const float StepStamina = 20f;
        public const float StepSpeed = 0.05f;
        public const float StepMana = 18f;
        public const int MaxLevel = 5;
        public const int CostStep = 40;

        /// Опыт — за донесённую добычу, убийства и доехавшие обозы; за своих — нет.
        public const int ResourcePerPoint = 4;
        public const int XpUnitKill = 10;
        public const int XpLeaderKill = 30;
        public const int XpCaravan = 35;

        /// Цена следующего уровня; -1 — выше некуда.
        public static int CostOf(int level)
        {
            if (level < 0 || level >= MaxLevel) return -1;
            return CostStep * (level + 1);
        }
    }

    public class Vitals
    {
        public const float BaseHealth = 100f;
        public const float BaseMana = 100f;
        public const float ManaRegen = 2.5f;
        public const float BaseStamina = 100f;
        public const float StaminaRunDrain = 10f;
        public const float StaminaJump = 12f;
        public const float StaminaRegen = 12f;
        /// «Второе дыхание»: выдохшись, бежать снова — только набрав столько.
        public const float StaminaFloor = 15f;
        /// Отдышаться перед возвратом: иначе частые нажатия давали вечный бег.
        public const float StaminaRest = 0.6f;

        public readonly int[] Levels = new int[4];
        /// Прокачка заклинаний по AbilityKind (Abilities.Upgradable): за тот же опыт.
        public readonly int[] SpellLevels = new int[6];
        public int Experience;
        public float Health;
        public bool Alive = true;
        public float Mana;
        public float Stamina;
        /// Консоль плейтеста: выносливость не тратится («stamina»).
        public bool EndlessStamina;
        public bool Winded;
        float _restLeft;

        public Vitals()
        {
            Health = MaxHealth;
            Mana = MaxMana;
            Stamina = MaxStamina;
        }

        public float MaxHealth { get { return BaseHealth + Progression.StepHealth * Levels[(int)Stat.Health]; } }
        public float MaxStamina { get { return BaseStamina + Progression.StepStamina * Levels[(int)Stat.Stamina]; } }
        public float MaxMana { get { return BaseMana + Progression.StepMana * Levels[(int)Stat.Mana]; } }
        public float RunScale { get { return Movement.RunScale + Progression.StepSpeed * Levels[(int)Stat.Speed]; } }

        /// Урон; возвращает снятое. Ноль — мёртв.
        public float ApplyDamage(float amount)
        {
            if (!Alive || amount <= 0f) return 0f;
            float before = Health;
            Health = Math.Max(0f, Health - amount);
            if (Health <= 0f) Alive = false;
            return before - Health;
        }

        public void Heal(float amount)
        {
            if (!Alive) return;
            Health = Math.Min(MaxHealth, Health + amount);
        }

        public void Revive()
        {
            Health = MaxHealth;
            Alive = true;
        }

        public void TickMana(float delta)
        {
            Mana = Math.Min(MaxMana, Mana + ManaRegen * delta);
        }

        public bool SpendMana(float cost)
        {
            if (Mana < cost) return false;
            Mana -= cost;
            return true;
        }

        /// Такт выносливости. wantsRun — жмёт бег и есть куда бежать; mounted —
        /// верхом (устаёт лошадь, а не всадник). Возвращает, бежит ли на самом деле.
        public bool TickRun(float delta, bool wantsRun, bool mounted)
        {
            if (EndlessStamina)
            {
                Stamina = MaxStamina;
                Winded = false;
                return wantsRun;
            }
            bool running = wantsRun;
            if (running && !mounted)
            {
                if (Winded || Stamina <= 0f)
                {
                    Winded = true;
                    running = false;
                }
                else
                {
                    Stamina = Math.Max(0f, Stamina - StaminaRunDrain * delta);
                    _restLeft = StaminaRest;
                    if (Stamina <= 0f) Winded = true;
                }
            }
            if (!running)
            {
                _restLeft = Math.Max(0f, _restLeft - delta);
                if (_restLeft <= 0f && Stamina < MaxStamina)
                    Stamina = Math.Min(MaxStamina, Stamina + StaminaRegen * delta);
            }
            if (Winded && Stamina >= StaminaFloor) Winded = false;
            return running;
        }

        /// Потратить силы (рывок): восстановление начнётся после передышки.
        public void SpendStamina(float amount)
        {
            if (EndlessStamina) return;
            Stamina = Math.Max(0f, Stamina - amount);
            _restLeft = StaminaRest;
        }

        /// Прыжок стоит сил (верхом — нет). Возвращает, прыгнул ли.
        public bool TryJump(bool mounted)
        {
            if (mounted || EndlessStamina) return true;
            if (Stamina < StaminaJump) return false;
            Stamina = Math.Max(0f, Stamina - StaminaJump);
            _restLeft = StaminaRest;
            return true;
        }

        /// Прокачать заклинание за опыт — по той же шкале цен, что и уровни.
        public bool BuySpellLevel(AbilityKind kind)
        {
            if (!Abilities.Upgradable(kind)) return false;
            int level = SpellLevels[(int)kind];
            if (level >= Abilities.MaxSpellLevel) return false;
            int cost = Progression.CostOf(level);
            if (cost < 0 || Experience < cost) return false;
            Experience -= cost;
            SpellLevels[(int)kind] += 1;
            return true;
        }

        /// Купить уровень за опыт. Прибавка — поверх базы; здоровье и ману
        /// добавляем сразу, чтобы купленное было видно.
        public bool BuyLevel(Stat stat)
        {
            int cost = Progression.CostOf(Levels[(int)stat]);
            if (cost < 0 || Experience < cost) return false;
            Experience -= cost;
            Levels[(int)stat] += 1;
            if (stat == Stat.Health) Health += Progression.StepHealth;
            if (stat == Stat.Mana) Mana += Progression.StepMana;
            return true;
        }
    }
}
