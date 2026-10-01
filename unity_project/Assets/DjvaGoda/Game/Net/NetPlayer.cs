// Сетевая половина персонажа. Владелец ведёт движение сам и пишет положение;
// остальные сглаживают присланное. Здоровье, раны, снаряжение пишет только
// хост; заявки (удар, сделка, стройка) идут хосту Rpc с проверкой отправителя.
//
// Положение — своими переменными с правом записи у владельца, а не
// NetworkTransform: его режим «пишет владелец» менялся между версиями пакета,
// а здесь право видно в одной строке.
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
        /// Положение и взгляд — пишет владелец: клиент считает своё движение сам.
        public readonly NetworkVariable<Vector3> Position = new NetworkVariable<Vector3>(Vector3.zero,
            NetworkVariableReadPermission.Everyone, NetworkVariableWritePermission.Owner);
        public readonly NetworkVariable<float> Yaw = new NetworkVariable<float>(0f,
            NetworkVariableReadPermission.Everyone, NetworkVariableWritePermission.Owner);
        public readonly NetworkVariable<float> Pitch = new NetworkVariable<float>(0f,
            NetworkVariableReadPermission.Everyone, NetworkVariableWritePermission.Owner);
        /// Считает хост.
        public readonly NetworkVariable<float> Health = new NetworkVariable<float>(Vitals.BaseHealth);
        public readonly NetworkVariable<int> Severed = new NetworkVariable<int>();
        public readonly NetworkVariable<int> Crippled = new NetworkVariable<int>();
        public readonly NetworkVariable<int> GearTier = new NetworkVariable<int>();
        public readonly NetworkVariable<int> ArmorTier = new NetworkVariable<int>();

        PlayerCharacter _character;

        void Awake() { _character = GetComponent<PlayerCharacter>(); }

        public override void OnNetworkSpawn()
        {
            _character.Faction = (Faction)Side.Value;
            _character.LocalControl = IsOwner;
            _character.Simulate = IsOwner;
            if (IsOwner)
            {
                var rig = Object.FindAnyObjectByType<CameraRig>();
                if (rig != null) rig.Target = _character;
            }
        }

        void Update()
        {
            if (!IsSpawned) return;
            if (IsOwner)
            {
                // Своё движение — своё: пишем, только если заметно сдвинулись.
                if ((Position.Value - transform.position).sqrMagnitude > 0.0004f) Position.Value = transform.position;
                if (Mathf.Abs(Yaw.Value - _character.Yaw) > 0.001f) Yaw.Value = _character.Yaw;
                if (Mathf.Abs(Pitch.Value - _character.Pitch) > 0.001f) Pitch.Value = _character.Pitch;
            }
            else
            {
                float t = Mathf.Clamp01(Time.deltaTime * 14f);
                transform.position = Vector3.Lerp(transform.position, Position.Value, t);
                _character.Yaw = Mathf.LerpAngle(_character.Yaw * Mathf.Rad2Deg, Yaw.Value * Mathf.Rad2Deg, t) * Mathf.Deg2Rad;
                _character.Pitch = Pitch.Value;
                transform.rotation = CoreSpace.YawToRotation(_character.Yaw);
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
