// Бой персонажа (перенос player.gd: _update_attack, request_attack,
// _server_swing_melee, _apply_melee_effect).
//
// Модель прав Godot-версии: владелец выбирает оружие и жмёт удар — замах и
// откат у него сразу, чтобы удар ощущался мгновенным; урон решает ТОЛЬКО хост
// по заявке (NetPlayer.AttackRpc). Хост берёт точку удара свою, а не присланную
// (разошлась больше чем на 4 м — заявка отклонена), сам считает откат, проверяет
// руки и оружие стороны, снимает стрелу. Без сети (одиночный загрузчик) хост —
// сам персонаж.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    [RequireComponent(typeof(PlayerCharacter))]
    public class PlayerCombat : MonoBehaviour
    {
        public const float MaxOriginDrift = 4f;

        public WeaponKind Weapon;
        /// Сбит молотом: не бьёт и не колдует. Пишет хост.
        public float Stagger;
        /// Откат у себя — для замаха и полосы на экране.
        public float Cooldown { get; private set; }
        public float CooldownFull { get; private set; }
        public string Refusal { get; private set; }
        /// Держать удар без мыши (ключ -attack: проверка боя по сети).
        public bool ScriptedAttack;

        PlayerCharacter _character;
        NetPlayer _net;
        float _serverCooldown;
        float _refusalLeft;

        void Awake()
        {
            _character = GetComponent<PlayerCharacter>();
            _net = GetComponent<NetPlayer>();
        }

        void Start() { Weapon = Factions.DefaultWeapon(_character.Faction); }

        bool Hosting { get { return _net == null || !_net.IsSpawned || _net.IsServer; } }

        float CooldownOf(WeaponKind kind)
        {
            float rally = _character.Spells.Rally > 0f ? Abilities.RallyAttackScale : 1f;
            return Weapons.Cooldown[(int)kind] * _character.Body.AttackSpeedScale() * rally
                * Weapons.GearCooldown(_character.Kit.GearTier);
        }

        public bool Allowed(WeaponKind kind)
        {
            if (!Factions.AllowsWeapon(_character.Faction, kind)) return false;
            return Weapons.IsMelee(kind) ? _character.Body.CanAttackMelee() : _character.Body.CanAttackRanged();
        }

        void Update()
        {
            float delta = Time.deltaTime;
            Cooldown = Mathf.Max(0f, Cooldown - delta);
            _serverCooldown = Mathf.Max(0f, _serverCooldown - delta);
            if (Hosting) Stagger = Mathf.Max(0f, Stagger - delta);
            _refusalLeft -= delta;
            HitAge += delta;
            if (_refusalLeft <= 0f) Refusal = null;
            if (!_character.LocalControl || !_character.Alive) return;

            var set = Factions.WeaponsOf(_character.Faction);
            for (int slot = 0; slot < 4; slot++)
                if (slot < set.Length && GameInput.Pressed("weapon_" + (slot + 1))) Weapon = set[slot];

            bool wants = ScriptedAttack || (_character.Scripted == null && Cursor.lockState == CursorLockMode.Locked && GameInput.Held("attack"));
            if (!wants) return;
            if (Cooldown > 0f || Stagger > 0f || _character.Spells.Paralysis > 0f || !Allowed(Weapon)) return;
            CooldownFull = CooldownOf(Weapon);
            Cooldown = CooldownFull;
            var origin = Aim.Origin(_character.Feet);
            var rig = Object.FindAnyObjectByType<CameraRig>();
            var dir = _character.AimDirection(rig != null ? rig.Camera : null);
            if (Hosting) ServerAttack(Weapon, origin, dir);
            else _net.AttackRpc((int)Weapon, origin.ToUnity(), dir.ToUnity());
        }

        /// Отметка попадания: когда, в голову ли, добил ли.
        public float HitAge { get; private set; } = 99f;
        public bool HitHead { get; private set; }
        public bool HitKill { get; private set; }

        public void ShowHit(bool head, bool killed)
        {
            HitAge = 0f;
            HitHead = head;
            HitKill = killed;
        }

        public void Refuse(string why)
        {
            Refusal = why;
            _refusalLeft = 3f;
        }

        /// Удар у хоста. Клиент сообщает только намерение: оружие и направление.
        public void ServerAttack(WeaponKind kind, V3 origin, V3 dir)
        {
            if (!_character.Alive || _serverCooldown > 0f || Stagger > 0f || _character.Spells.Paralysis > 0f) return;
            if (!Allowed(kind)) return;
            var here = Aim.Origin(_character.Feet);
            if (origin.Distance(here) > MaxOriginDrift)
            {
                Debug.LogWarning("Заявка на удар отклонена: точка удара разошлась на " + origin.Distance(here).ToString("0.0") + " м");
                return;
            }
            var aim = dir.Normalized();
            if (aim.Length() < 0.5f) return;
            // Чуть меньше отката владельца: заявка едет по сети, и откат хоста не
            // должен съедать каждый второй удар у того, кто держит кнопку.
            _serverCooldown = CooldownOf(kind) * 0.9f;
            if (Weapons.IsMelee(kind))
            {
                // Тем же ударом рубят дерево и бьют камень: отдельной кнопки добычи нет.
                if (!Harvest(kind, here, aim)) Swing(kind, here, aim);
                return;
            }
            if (Weapons.UsesArrows(kind))
            {
                if (_character.Kit.Arrows <= 0)
                {
                    Tell("стрелы кончились — возьмись за меч или докупи в лавке");
                    return;
                }
                _character.Kit.Arrows--;
            }
            var shot = Shot.Fire(kind, here, aim, _character, _character.Kit.GearTier);
            if (_net != null && _net.IsSpawned)
            {
                var net = _net;
                net.ShotRpc(shot.Id, (int)kind, here.ToUnity(), aim.ToUnity());
                shot.Ended = (id, at) => { if (net != null && net.IsSpawned) net.ShotEndRpc(id, at); };
            }
        }

        /// Сказать владельцу (у хоста): по сети — заявкой ему, без сети — сразу.
        public void Tell(string why)
        {
            if (_net != null && _net.IsSpawned && !_net.IsOwner) _net.RefuseRpc(why);
            else Refuse(why);
        }

        /// Добыча: луч перед глазами упёрся в дерево или камень — ресурс в
        /// ношу стороны, источнику удар. Инструмент — то же оружие: топор лучше
        /// рубит лес, молот — камень (Weapons.HarvestBonus).
        bool Harvest(WeaponKind kind, V3 origin, V3 aim)
        {
            RaycastHit hit;
            if (!Physics.Raycast(origin.ToUnity(), aim.ToUnity(), out hit, Res.HarvestRange, HitZone.WorldMask, QueryTriggerInteraction.Ignore))
                return false;
            var source = hit.collider.GetComponentInParent<Harvestable>();
            if (source == null) return false;
            int amount = MeleeRules.HarvestYield(kind, source.Resource);
            int taken = Treasury.Of(_character.Faction).Add((int)source.Resource, amount);
            if (taken < amount) Tell("ноша полна — неси на склад");
            bool gone;
            if (source.TreeIndex >= 0)
            {
                var world = Object.FindAnyObjectByType<World>();
                gone = world == null || world.Forest.Hit(source.TreeIndex) <= 0;
            }
            else
            {
                source.HitsLeft--;
                gone = source.HitsLeft <= 0;
            }
            if (gone) MatchNet.Deplete(source.Key);
            return true;
        }

        /// Ближний бой: зоны в сфере удара, в дуге перед глазами; по цели — одна, самая ценная.
        void Swing(WeaponKind kind, V3 origin, V3 aim)
        {
            var hits = new List<ZoneHit>();
            foreach (var c in Physics.OverlapSphere(origin.ToUnity(), Weapons.MeleeRange(kind), HitZone.Mask, QueryTriggerInteraction.Collide))
            {
                var zone = c.GetComponent<HitZone>();
                if (zone == null || zone.Owner == null || !zone.Owner.Alive) continue;
                hits.Add(new ZoneHit(zone.Owner.Id, zone.Zone, c.transform.position.ToCore()));
            }
            var best = MeleeRules.BestZones(hits, aim, origin, id =>
            {
                var actor = Actor.ById(id);
                return actor != null ? actor.At : origin;
            }, _character.Id);
            foreach (var pair in best)
            {
                var target = Actor.ById(pair.Key);
                if (target == null) continue;
                float damage = DamageRules.Outgoing(kind, pair.Value.Zone, _character.Kit.GearTier, _character.Spells.Wither > 0f);
                Actor.Strike(target, damage, pair.Value.Zone, kind, false, _character);
                Effect(kind, target);
            }
        }

        /// Сверх урона: топор пускает кровь (не каждым ударом), молот сбивает.
        static void Effect(WeaponKind kind, Actor target)
        {
            var victim = target as PlayerCharacter;
            if (victim == null) return;
            if (kind == WeaponKind.Axe && Random.value < Weapons.AxeBleedChance) victim.Body.StartBleeding();
            if (kind == WeaponKind.Hammer)
            {
                var combat = victim.GetComponent<PlayerCombat>();
                if (combat != null) combat.Stagger = Mathf.Max(combat.Stagger, Weapons.HammerStagger);
            }
        }
    }
}
