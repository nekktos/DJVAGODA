// Сетевая половина персонажа. Владелец ведёт движение сам; положение и
// поворот везёт NetworkTransform с правом записи у владельца (AuthorityMode
// Owner) — со сглаживанием по тикам, остальные видят плавное движение.
// Здоровье, раны, снаряжение, смерть пишет только хост; заявки (удар,
// перевязка, сделка, стройка) идут хосту Rpc с проверкой отправителя.
using System.Collections.Generic;
using DjvaGoda.Core;
using Unity.Netcode;
using UnityEngine;

namespace DjvaGoda.Game
{
    /// Состояние заклинаний для клиентов: откаты, сроки, каст, мана. Считает хост.
    public struct SpellSync : INetworkSerializable, System.IEquatable<SpellSync>
    {
        public float Mana, Rally, Paralysis, Wither, Blind, CastLeft;
        public int CastKind;
        public float Cd0, Cd1, Cd2, Cd3, Cd4, Cd5;

        public void NetworkSerialize<T>(BufferSerializer<T> s) where T : IReaderWriter
        {
            s.SerializeValue(ref Mana);
            s.SerializeValue(ref Rally);
            s.SerializeValue(ref Paralysis);
            s.SerializeValue(ref Wither);
            s.SerializeValue(ref Blind);
            s.SerializeValue(ref CastLeft);
            s.SerializeValue(ref CastKind);
            s.SerializeValue(ref Cd0);
            s.SerializeValue(ref Cd1);
            s.SerializeValue(ref Cd2);
            s.SerializeValue(ref Cd3);
            s.SerializeValue(ref Cd4);
            s.SerializeValue(ref Cd5);
        }

        /// Десятые доли секунды: таймеры тикают каждый кадр, а слать их чаще незачем.
        static bool Near(float a, float b) { return System.Math.Abs(a - b) < 0.1f; }

        public bool Equals(SpellSync o)
        {
            return Near(Mana, o.Mana) && Near(Rally, o.Rally) && Near(Paralysis, o.Paralysis) && Near(Wither, o.Wither)
                && Near(Blind, o.Blind) && Near(CastLeft, o.CastLeft) && CastKind == o.CastKind
                && Near(Cd0, o.Cd0) && Near(Cd1, o.Cd1) && Near(Cd2, o.Cd2) && Near(Cd3, o.Cd3) && Near(Cd4, o.Cd4) && Near(Cd5, o.Cd5);
        }

        public static SpellSync Of(Vitals vitals, SpellState spells)
        {
            var c = spells.Cooldowns;
            return new SpellSync
            {
                Mana = vitals.Mana, Rally = spells.Rally, Paralysis = spells.Paralysis, Wither = spells.Wither,
                Blind = spells.Blind, CastLeft = spells.CastLeft, CastKind = spells.CastKind.HasValue ? (int)spells.CastKind.Value : -1,
                Cd0 = c[0], Cd1 = c[1], Cd2 = c[2], Cd3 = c[3], Cd4 = c[4], Cd5 = c[5],
            };
        }

        public void Apply(Vitals vitals, SpellState spells)
        {
            vitals.Mana = Mana;
            spells.Rally = Rally;
            spells.Paralysis = Paralysis;
            spells.Wither = Wither;
            spells.Blind = Blind;
            spells.MirrorCast(CastKind >= 0 ? (AbilityKind?)CastKind : null, CastLeft);
            var c = spells.Cooldowns;
            c[0] = Cd0; c[1] = Cd1; c[2] = Cd2; c[3] = Cd3; c[4] = Cd4; c[5] = Cd5;
        }
    }

    [RequireComponent(typeof(PlayerCharacter))]
    public class NetPlayer : NetworkBehaviour
    {
        public readonly NetworkVariable<int> Side = new NetworkVariable<int>((int)Faction.Guard);
        public readonly NetworkVariable<int> Slot = new NetworkVariable<int>();
        /// Точка появления от хоста. Положением правит владелец (NetworkTransform
        /// Owner), и место спавна с хоста он не берёт — ставит себя сам.
        public readonly NetworkVariable<Vector3> SpawnAt = new NetworkVariable<Vector3>();
        /// Наклон головы — пишет владелец (поворот тела везёт NetworkTransform).
        public readonly NetworkVariable<float> Pitch = new NetworkVariable<float>(0f,
            NetworkVariableReadPermission.Everyone, NetworkVariableWritePermission.Owner);
        /// Считает хост.
        public readonly NetworkVariable<float> Health = new NetworkVariable<float>(Vitals.BaseHealth);
        public readonly NetworkVariable<bool> Dead = new NetworkVariable<bool>();
        /// Сколько осталось до возрождения; меньше нуля — не встанет (вожак).
        public readonly NetworkVariable<float> RespawnIn = new NetworkVariable<float>();
        public readonly NetworkVariable<int> Severed = new NetworkVariable<int>();
        public readonly NetworkVariable<int> Crippled = new NetworkVariable<int>();
        public readonly NetworkVariable<bool> Bleeding = new NetworkVariable<bool>();
        public readonly NetworkVariable<int> Bandages = new NetworkVariable<int>();
        public readonly NetworkVariable<int> GearTier = new NetworkVariable<int>();
        public readonly NetworkVariable<int> ArmorTier = new NetworkVariable<int>();
        public readonly NetworkVariable<int> Arrows = new NetworkVariable<int>();
        public readonly NetworkVariable<int> PotionsHeal = new NetworkVariable<int>();
        public readonly NetworkVariable<int> PotionsMana = new NetworkVariable<int>();
        public readonly NetworkVariable<float> Stagger = new NetworkVariable<float>();
        public readonly NetworkVariable<SpellSync> Spells = new NetworkVariable<SpellSync>();
        /// Оружие в руке — выбирает владелец, видят все (WeaponView).
        public readonly NetworkVariable<int> WeaponHeld = new NetworkVariable<int>(0,
            NetworkVariableReadPermission.Everyone, NetworkVariableWritePermission.Owner);

        /// Сторона и место, назначенные хостом до спавна: в сетевые переменные
        /// их пишет OnNetworkSpawn — до спавна переменная ещё не привязана.
        [System.NonSerialized] public int AssignedSide = (int)Faction.Guard;
        [System.NonSerialized] public int AssignedSlot;
        [System.NonSerialized] public Vector3 AssignedSpawn;

        PlayerCharacter _character;
        PlayerCombat _combat;
        PlayerSpells _spells;
        float _deadFor;
        bool _wasAlive = true;

        void Awake()
        {
            _character = GetComponent<PlayerCharacter>();
            _combat = GetComponent<PlayerCombat>();
            _spells = GetComponent<PlayerSpells>();
        }

        public override void OnNetworkSpawn()
        {
            if (IsServer)
            {
                Side.Value = AssignedSide;
                Slot.Value = AssignedSlot;
                SpawnAt.Value = AssignedSpawn;
            }
            _character.Faction = (Faction)Side.Value;
            // Вожак злодея — его единственный персонаж: его смерть окончательна.
            _character.Kit.IsLeader = _character.Faction == Faction.Villain;
            Bootstrap.AddBody(transform, (Faction)Side.Value);
            name = "Игрок " + OwnerClientId + " (" + Factions.Names[Side.Value] + ")";
            _character.LocalControl = IsOwner;
            _character.Simulate = IsOwner;
            if (IsOwner)
            {
                _character.Teleport(SpawnAt.Value);
                if (!IsServer) _character.Bandaged = () => BandageRpc();
                var rig = Object.FindAnyObjectByType<CameraRig>();
                if (rig != null) rig.Target = _character;
            }
        }

        void Update()
        {
            if (!IsSpawned) return;
            if (IsOwner)
            {
                if (Mathf.Abs(Pitch.Value - _character.Pitch) > 0.001f) Pitch.Value = _character.Pitch;
                if (_combat != null && WeaponHeld.Value != (int)_combat.Weapon) WeaponHeld.Value = (int)_combat.Weapon;
            }
            else
            {
                // Поворот тела пришёл в transform — yaw ядра из него.
                _character.Yaw = CoreSpace.RotationToYaw(transform);
                _character.Pitch = Pitch.Value;
                if (_combat != null) _combat.Weapon = (WeaponKind)WeaponHeld.Value;
            }
            if (IsServer)
            {
                ServerTick(Time.deltaTime);
                Health.Value = _character.Vitals.Health;
                Dead.Value = !_character.Vitals.Alive;
                Severed.Value = _character.Body.SeveredMask;
                Crippled.Value = _character.Body.CrippledMask;
                Bleeding.Value = _character.Body.Bleeding;
                Bandages.Value = _character.Body.Bandages;
                GearTier.Value = _character.Kit.GearTier;
                ArmorTier.Value = _character.Kit.ArmorTier;
                Arrows.Value = _character.Kit.Arrows;
                PotionsHeal.Value = _character.Kit.PotionsHeal;
                PotionsMana.Value = _character.Kit.PotionsMana;
                if (_combat != null) Stagger.Value = _combat.Stagger;
                Spells.Value = SpellSync.Of(_character.Vitals, _character.Spells);
            }
            else
            {
                _character.Vitals.Health = Health.Value;
                _character.Vitals.Alive = !Dead.Value;
                _character.Body.SeveredMask = Severed.Value;
                _character.Body.CrippledMask = Crippled.Value;
                _character.Body.Bleeding = Bleeding.Value;
                _character.Body.Bandages = Bandages.Value;
                _character.Kit.GearTier = GearTier.Value;
                _character.Kit.ArmorTier = ArmorTier.Value;
                _character.Kit.Arrows = Arrows.Value;
                _character.Kit.PotionsHeal = PotionsHeal.Value;
                _character.Kit.PotionsMana = PotionsMana.Value;
                if (_combat != null) _combat.Stagger = Stagger.Value;
                Spells.Value.Apply(_character.Vitals, _character.Spells);
            }
        }

        /// Хост: раны точат здоровье, павший встаёт по правилам возрождения.
        void ServerTick(float delta)
        {
            if (_character.Vitals.Alive)
            {
                // Кровотечение и натёртые протезы — урон у хоста.
                float wound = _character.Body.Tick(delta);
                if (wound > 0f) _character.Vitals.ApplyDamage(wound);
            }
            bool alive = _character.Vitals.Alive;
            // Отсчёт — с мгновения смерти, чем бы ни убило (удар, снаряд, кровь).
            if (!alive && _wasAlive) _deadFor = 0f;
            _wasAlive = alive;
            if (alive) return;
            var verdict = Respawn.Verdict(_character.Faction, _character.Kit.IsLeader,
                Respawn.ElfHousesStart.Length, false);
            if (verdict == RespawnVerdict.Never)
            {
                RespawnIn.Value = -1f;
                return;
            }
            _deadFor += delta;
            RespawnIn.Value = Mathf.Max(0f, Respawn.Delay - _deadFor);
            if (_deadFor < Respawn.Delay) return;
            var at = Respawn.SpawnPoint(_character.Faction, Slot.Value, true, _character.Feet,
                new List<V3>(Respawn.ElfHousesStart)) + new V3(0f, 1f, 0f);
            _character.Vitals.Revive();
            _character.Body.Reset();
            _character.Spells.OnDamaged();
            if (IsOwner) _character.Teleport(at.ToUnity());
            else RespawnRpc(at.ToUnity());
        }

        /// Владельцу: встать на точку возрождения (положением правит он).
        [Rpc(SendTo.Owner)]
        void RespawnRpc(Vector3 at) { _character.Teleport(at); }

        /// Заявка на удар: оружие, откуда и куда. Решает хост (PlayerCombat.ServerAttack).
        [Rpc(SendTo.Server)]
        public void AttackRpc(int kind, Vector3 origin, Vector3 dir, RpcParams rpcParams = default(RpcParams))
        {
            if (rpcParams.Receive.SenderClientId != OwnerClientId) return;
            if (kind < 0 || kind >= Weapons.Names.Length || _combat == null) return;
            _combat.ServerAttack((WeaponKind)kind, origin.ToCore(), dir.ToCore());
        }

        /// Заявка на заклинание. Решает хост (PlayerSpells.ServerCast).
        [Rpc(SendTo.Server)]
        public void CastRpc(int kind, RpcParams rpcParams = default(RpcParams))
        {
            if (rpcParams.Receive.SenderClientId != OwnerClientId) return;
            if (kind < 0 || kind >= Abilities.Names.Length || _spells == null) return;
            _spells.ServerCast((AbilityKind)kind);
        }

        /// Вспышка заклинания — всем, и хосту тоже.
        [Rpc(SendTo.Everyone)]
        public void SpellFxRpc(int kind, Vector3 at) { SpellFx.Show((AbilityKind)kind, at); }

        /// Заявка на сделку у места (лавка, кузня, постройка) или зелье. Решает хост (Shop.ServerDeal).
        [Rpc(SendTo.Server)]
        public void DealRpc(int deal, int arg, RpcParams rpcParams = default(RpcParams))
        {
            if (rpcParams.Receive.SenderClientId != OwnerClientId) return;
            var shop = GetComponent<Shop>();
            if (shop != null && deal >= 0 && deal <= (int)DealKind.Potion) shop.ServerDeal((DealKind)deal, arg);
        }

        /// Хозяйство из вида сверху: −1 — нанять батрака, иначе — роль. Решает хост.
        [Rpc(SendTo.Server)]
        public void LabourRpc(int role, RpcParams rpcParams = default(RpcParams))
        {
            if (rpcParams.Receive.SenderClientId != OwnerClientId) return;
            var builder = GetComponent<Builder>();
            if (builder != null) builder.ServerLabour(role);
        }

        /// Заявка на перевязку: бинт и кровь — у хоста.
        [Rpc(SendTo.Server)]
        void BandageRpc(RpcParams rpcParams = default(RpcParams))
        {
            if (rpcParams.Receive.SenderClientId != OwnerClientId) return;
            if (_character.Vitals.Alive) _character.Body.ApplyBandage();
        }

        /// Попадание — владельцу на прицел.
        [Rpc(SendTo.Owner)]
        public void HitRpc(bool head, bool killed)
        {
            if (_combat != null) _combat.ShowHit(head, killed);
        }

        /// Отказ хоста — владельцу на экран.
        [Rpc(SendTo.Owner)]
        public void RefuseRpc(string why)
        {
            if (_combat != null) _combat.Refuse(why);
        }

        /// Выстрел: клиенты рисуют тот же полёт.
        [Rpc(SendTo.NotServer)]
        public void ShotRpc(int id, int kind, Vector3 origin, Vector3 dir)
        {
            Shot.Show(id, (WeaponKind)kind, origin.ToCore(), dir.ToCore());
        }

        [Rpc(SendTo.NotServer)]
        public void ShotEndRpc(int id, Vector3 at) { Shot.End(id, at); }

        /// Заявка на постройку. Хост проверяет отправителя, дальше — сделка по правилам ядра.
        [Rpc(SendTo.Server)]
        public void BuildRpc(int kind, Vector3 at, RpcParams rpcParams = default(RpcParams))
        {
            if (rpcParams.Receive.SenderClientId != OwnerClientId) return;
            if (kind < 0 || kind >= Res.BuildingNames.Length) return;
            var builder = GetComponent<Builder>();
            if (builder != null) builder.ServerBuild((BuildingKind)kind, at.ToCore());
        }
    }
}
