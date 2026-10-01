// Заклинания персонажа: откаты, мана, долгий каст, проклятия на нём
// (перенос из player.gd, GDD 3.1–3.2).
//
// Контрплей против магии злодея: каст паралича 1.75 с срывается любым уроном,
// сорванный каст не стоит ни отката, ни маны; после паралича — окно
// неуязвимости 25 с; любой урон снимает паралич досрочно.
using System;

namespace DjvaGoda.Core
{
    public enum CastStart { Refused, Instant, Casting }

    public class SpellState
    {
        public readonly float[] Cooldowns = new float[Enum.GetValues(typeof(AbilityKind)).Length];
        public float Paralysis;
        public float Wither;
        public float Blind;
        /// Клич леса: сколько ещё действует.
        public float Rally;
        float _immunity;
        bool _wasParalysed;
        AbilityKind? _casting;
        float _castLeft;

        public bool Casting { get { return _castLeft > 0f; } }
        public float CastLeft { get { return _castLeft; } }
        public AbilityKind? CastKind { get { return _casting; } }

        /// Каст, присланный хостом (клиент сам заклинания не считает).
        public void MirrorCast(AbilityKind? kind, float left)
        {
            _casting = kind;
            _castLeft = left;
        }

        public bool Ready(AbilityKind kind) { return Cooldowns[(int)kind] <= 0f; }

        /// Начать заклинание. Проверки — как у хоста: своё ли, откат, мана,
        /// рука, не парализован. Мгновенное хост исполняет сразу (и платит через
        /// Finish), долгое — ждёт каста.
        public CastStart Begin(Faction side, AbilityKind kind, Vitals vitals, BodyState body, out string refusal)
        {
            refusal = null;
            if (!Factions.AllowsAbility(side, kind) || !Ready(kind)) return CastStart.Refused;
            if (vitals.Mana < Abilities.ManaCost[(int)kind])
            {
                refusal = "не хватает маны: нужно " + (int)Abilities.ManaCost[(int)kind] + ", есть " + (int)vitals.Mana;
                return CastStart.Refused;
            }
            if (body != null && !body.CanAttackRanged()) return CastStart.Refused;
            if (Paralysis > 0f) return CastStart.Refused;
            float cast = Abilities.CastTime(kind);
            if (cast > 0f)
            {
                if (Casting) return CastStart.Refused;
                _casting = kind;
                _castLeft = cast;
                return CastStart.Casting;
            }
            return CastStart.Instant;
        }

        /// Заклинание сработало: откат и мана списываются ТОЛЬКО теперь.
        public void Pay(AbilityKind kind, Vitals vitals)
        {
            vitals.Mana = Math.Max(0f, vitals.Mana - Abilities.ManaCost[(int)kind]);
            Cooldowns[(int)kind] = Abilities.Cooldown[(int)kind];
        }

        /// По кастующему попали: каст сорван, паралич снят досрочно.
        public void OnDamaged()
        {
            _castLeft = 0f;
            _casting = null;
            Paralysis = 0f;
        }

        /// Наложить паралич; false — цель под окном неуязвимости.
        public bool ApplyParalysis(float seconds)
        {
            if (_immunity > 0f) return false;
            Paralysis = Math.Max(Paralysis, seconds);
            _wasParalysed = true;
            return true;
        }

        public void ApplyWither(float seconds, BodyState body)
        {
            Wither = Math.Max(Wither, seconds);
            if (body != null) body.StartBleeding();
        }

        public void ApplyBlind(float seconds) { Blind = Math.Max(Blind, seconds); }

        /// Увядший бьёт слабее, но не перестаёт драться.
        public float CurseDamageScale() { return Wither > 0f ? Abilities.WitherDamageScale : 1f; }

        /// Такт хоста. Возвращает заклинание, чей каст завершился, — его надо исполнить.
        public AbilityKind? Tick(float delta)
        {
            for (int i = 0; i < Cooldowns.Length; i++)
                if (Cooldowns[i] > 0f) Cooldowns[i] = Math.Max(0f, Cooldowns[i] - delta);
            Rally = Math.Max(0f, Rally - delta);
            Paralysis = Math.Max(0f, Paralysis - delta);
            Wither = Math.Max(0f, Wither - delta);
            Blind = Math.Max(0f, Blind - delta);
            _immunity = Math.Max(0f, _immunity - delta);
            if (Paralysis > 0f)
            {
                _wasParalysed = true;
            }
            else if (_wasParalysed)
            {
                _wasParalysed = false;
                _immunity = Abilities.ParalysisImmunity;
            }
            if (_castLeft > 0f)
            {
                _castLeft -= delta;
                if (_castLeft <= 0f)
                {
                    var done = _casting;
                    _casting = null;
                    return done;
                }
            }
            return null;
        }
    }
}
