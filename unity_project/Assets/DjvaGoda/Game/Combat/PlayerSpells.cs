// Заклинания персонажа (перенос player.gd: _update_abilities, request_ability,
// _finish_cast, _server_cast_*).
//
// Как и урон, заклинания решает ХОСТ: владелец жмёт 4/5/6 и шлёт заявку
// (NetPlayer.CastRpc), хост проверяет (своё ли, откат, мана, рука, не
// парализован и не сбит — SpellState.Begin), долгий каст ждёт и срывается
// ударом, мана и откат списываются ТОЛЬКО когда заклинание сработало.
// Таймеры заклинаний и мана тикают у хоста, клиентам — сетевой переменной.
//
// Эльфы: лечение, клич леса, призыв волка. Злодей: паралич, увядание, слепота.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    [RequireComponent(typeof(PlayerCharacter))]
    public class PlayerSpells : MonoBehaviour
    {
        PlayerCharacter _character;
        PlayerCombat _combat;
        NetPlayer _net;
        readonly List<UnitAgent> _wolves = new List<UnitAgent>();

        /// Заклинание по ключу -cast (проверка без клавиатуры); −1 — нет.
        public int ScriptedCast = -1;

        void Awake()
        {
            _character = GetComponent<PlayerCharacter>();
            _combat = GetComponent<PlayerCombat>();
            _net = GetComponent<NetPlayer>();
        }

        bool Hosting { get { return _net == null || !_net.IsSpawned || _net.IsServer; } }

        void Update()
        {
            float delta = Time.deltaTime;
            if (Hosting)
            {
                if (_character.Alive)
                {
                    _character.Vitals.TickMana(delta);
                    var done = _character.Spells.Tick(delta);
                    if (done.HasValue) Finish(done.Value);
                }
                _wolves.RemoveAll(w => w == null || !w.Alive);
            }
            if (!_character.LocalControl || !_character.Alive) return;
            if (GameMode.Strategy && ScriptedCast < 0) return;
            var set = Factions.AbilitiesOf(_character.Faction);
            int wanted = -1;
            for (int slot = 0; slot < 3 && slot < set.Length; slot++)
                if (GameInput.Pressed("ability_" + (slot + 1))) wanted = (int)set[slot];
            if (wanted < 0 && ScriptedCast >= 0)
            {
                wanted = ScriptedCast;
                ScriptedCast = -1;
            }
            if (wanted < 0) return;
            var kind = (AbilityKind)wanted;
            if (!Factions.AllowsAbility(_character.Faction, kind) || !_character.Spells.Ready(kind)) return;
            if (Hosting) ServerCast(kind);
            else _net.CastRpc(wanted);
        }

        void Refuse(string why)
        {
            if (string.IsNullOrEmpty(why)) return;
            if (_combat != null) _combat.Tell(why);
        }

        /// Заявка у хоста.
        public void ServerCast(AbilityKind kind)
        {
            if (!_character.Alive) return;
            if (_combat != null && _combat.Stagger > 0f) return;
            string refusal;
            var start = _character.Spells.Begin(_character.Faction, kind, _character.Vitals, _character.Body, out refusal);
            if (start == CastStart.Refused)
            {
                Refuse(refusal);
                return;
            }
            if (start == CastStart.Casting)
            {
                Flash(kind);
                return;
            }
            if (!Run(kind)) return;
            _character.Spells.Pay(kind, _character.Vitals);
            Flash(kind);
        }

        /// Каст доведён до конца. Мана могла кончиться, пока шёл каст, — ещё раз.
        void Finish(AbilityKind kind)
        {
            if (_character.Vitals.Mana < Abilities.ManaCost[(int)kind])
            {
                Refuse("мана кончилась, пока шёл каст");
                return;
            }
            if (!Run(kind)) return;
            _character.Spells.Pay(kind, _character.Vitals);
            Flash(kind);
        }

        void Flash(AbilityKind kind)
        {
            if (_net != null && _net.IsSpawned) _net.SpellFxRpc((int)kind, transform.position);
            else SpellFx.Show(kind, transform.position);
        }

        bool Run(AbilityKind kind)
        {
            switch (kind)
            {
                case AbilityKind.Heal: return Heal();
                case AbilityKind.Rally: return Rally();
                case AbilityKind.Summon: return Summon();
                case AbilityKind.Paralysis: return Paralysis();
                case AbilityKind.Wither: return Curse(kind);
                case AbilityKind.Blind: return Curse(kind);
            }
            return false;
        }

        /// Свои рядом — персонажи своей стороны, и сам кастующий.
        List<PlayerCharacter> Allies(float radius)
        {
            var result = new List<PlayerCharacter>();
            foreach (var actor in Actor.All)
            {
                var other = actor as PlayerCharacter;
                if (other == null || !other.Alive || other.Faction != _character.Faction) continue;
                if (other.Feet.Distance(_character.Feet) <= radius) result.Add(other);
            }
            return result;
        }

        bool Heal()
        {
            int healed = 0;
            foreach (var ally in Allies(Abilities.RangeOf(AbilityKind.Heal)))
                if (SpellEffects.Heal(ally.Vitals, ally.Body)) healed++;
            if (healed == 0) Refuse("лечить некого: все свои рядом здоровы");
            return healed > 0;
        }

        bool Rally()
        {
            var allies = Allies(Abilities.RangeOf(AbilityKind.Rally));
            foreach (var ally in allies) ally.Spells.Rally = Abilities.RallyDuration;
            return allies.Count > 0;
        }

        /// Волк — боец-зверь: ходит за призвавшим и бьёт чужих.
        bool Summon()
        {
            if (!SpellEffects.CanSummon(_wolves.Count))
            {
                Refuse("волков уже двое");
                return false;
            }
            var at = SpellEffects.SummonPoint(_character.Feet, _character.Yaw);
            var go = Agents.Make(AgentRole.Beast, _character.Faction, at + new V3(0f, 0.5f, 0f), "Волк");
            var wolf = go.AddComponent<UnitAgent>();
            wolf.Setup(UnitKind.Beast, (int)_character.Faction, _wolves.Count, at, 40f);
            wolf.Commander = _character;
            wolf.CommanderFormation = FormationKind.Loose;
            var nav = Object.FindAnyObjectByType<NavWorld>();
            wolf.Nav = nav;
            wolf.Lifetime = Abilities.SummonLifetime;
            Agents.Show(go);
            _wolves.Add(wolf);
            return true;
        }

        Actor NearestEnemy(AbilityKind kind)
        {
            var seen = Actor.Around(_character.Feet, Abilities.RangeOf(kind), _character);
            var best = SpellEffects.NearestEnemy(_character.Side, _character.Feet, Abilities.RangeOf(kind), seen);
            return best.HasValue ? Actor.ById(best.Value.Id) : null;
        }

        /// Паралич: игрока — сковать; бойца — перевербовать на время.
        bool Paralysis()
        {
            var target = NearestEnemy(AbilityKind.Paralysis);
            if (target == null)
            {
                Refuse("паралич некому наложить: врага рядом нет");
                return false;
            }
            var player = target as PlayerCharacter;
            if (player != null)
            {
                if (player.Spells.ApplyParalysis(Abilities.ParalysisHold)) return true;
                Refuse("цель ещё не отошла от прошлого паралича");
                return false;
            }
            var unit = target as UnitAgent;
            if (unit == null || unit.Brain == null) return false;
            unit.Brain.Charm((int)_character.Faction, Abilities.ParalysisCharm, unit.At);
            return true;
        }

        /// Увядание и слепота — по ближайшему врагу.
        bool Curse(AbilityKind kind)
        {
            var target = NearestEnemy(kind);
            if (target == null)
            {
                Refuse(Abilities.NameOf(kind) + " некому наложить: врага рядом нет");
                return false;
            }
            var player = target as PlayerCharacter;
            if (kind == AbilityKind.Wither)
            {
                if (player != null) player.Spells.ApplyWither(Abilities.WitherDuration, player.Body);
                // У бойца ран нет: увядание для него — чистый урон.
                else Actor.Strike(target, SpellEffects.WitherUnitDamage, "torso", WeaponKind.Spell, false, _character);
                return true;
            }
            if (player != null)
            {
                player.Spells.ApplyBlind(Abilities.BlindDuration);
                return true;
            }
            Refuse("слепота действует только на игрока");
            return false;
        }
    }
}
