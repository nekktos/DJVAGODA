// Сетевая половина персонажа. Владелец ведёт движение сам; положение и
// поворот везёт NetworkTransform с правом записи у владельца (AuthorityMode
// Owner) — со сглаживанием по тикам, остальные видят плавное движение.
// Здоровье, раны, снаряжение пишет только хост; заявки (удар, сделка, стройка)
// идут хосту Rpc с проверкой отправителя.
using DjvaGoda.Core;
using Unity.Netcode;
using UnityEngine;

namespace DjvaGoda.Game
{
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
        public readonly NetworkVariable<int> Severed = new NetworkVariable<int>();
        public readonly NetworkVariable<int> Crippled = new NetworkVariable<int>();
        public readonly NetworkVariable<int> GearTier = new NetworkVariable<int>();
        public readonly NetworkVariable<int> ArmorTier = new NetworkVariable<int>();

        /// Сторона и место, назначенные хостом до спавна: в сетевые переменные
        /// их пишет OnNetworkSpawn — до спавна переменная ещё не привязана.
        [System.NonSerialized] public int AssignedSide = (int)Faction.Guard;
        [System.NonSerialized] public int AssignedSlot;
        [System.NonSerialized] public Vector3 AssignedSpawn;

        PlayerCharacter _character;

        void Awake() { _character = GetComponent<PlayerCharacter>(); }

        public override void OnNetworkSpawn()
        {
            if (IsServer)
            {
                Side.Value = AssignedSide;
                Slot.Value = AssignedSlot;
                SpawnAt.Value = AssignedSpawn;
            }
            _character.Faction = (Faction)Side.Value;
            Bootstrap.AddBody(transform, (Faction)Side.Value);
            name = "Игрок " + OwnerClientId + " (" + Factions.Names[Side.Value] + ")";
            _character.LocalControl = IsOwner;
            _character.Simulate = IsOwner;
            if (IsOwner)
            {
                // CharacterController помнит своё положение: без выключения
                // первый Move вернул бы персонажа туда, где его создали (в ноль).
                var controller = GetComponent<CharacterController>();
                controller.enabled = false;
                transform.position = SpawnAt.Value;
                controller.enabled = true;
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
            }
            else
            {
                // Поворот тела пришёл в transform — yaw ядра из него.
                _character.Yaw = CoreSpace.RotationToYaw(transform);
                _character.Pitch = Pitch.Value;
            }
            if (IsServer)
            {
                Health.Value = _character.Vitals.Health;
                Severed.Value = _character.Body.SeveredMask;
                Crippled.Value = _character.Body.CrippledMask;
                GearTier.Value = _character.Kit.GearTier;
                ArmorTier.Value = _character.Kit.ArmorTier;
            }
            else
            {
                _character.Vitals.Health = Health.Value;
                _character.Body.SeveredMask = Severed.Value;
                _character.Body.CrippledMask = Crippled.Value;
                _character.Kit.GearTier = GearTier.Value;
                _character.Kit.ArmorTier = ArmorTier.Value;
            }
        }

        /// Заявка на постройку. Хост проверяет отправителя, дальше — сделка по правилам ядра.
        [Rpc(SendTo.Server)]
        public void BuildRpc(int kind, Vector3 at, RpcParams rpcParams = default(RpcParams))
        {
            if (rpcParams.Receive.SenderClientId != OwnerClientId) return;
            // Сделка (Deals) и постановка (Placement) — в шаге «Экономика».
        }
    }
}
