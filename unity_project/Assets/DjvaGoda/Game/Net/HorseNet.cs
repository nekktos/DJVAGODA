// Сетевая половина лошади: под седлом ли (положение везёт NetworkTransform
// хоста). Клиент рисует её и прячет, пока на ней едут.
using Unity.Netcode;

namespace DjvaGoda.Game
{
    [UnityEngine.RequireComponent(typeof(HorseActor))]
    public class HorseNet : NetworkBehaviour
    {
        public readonly NetworkVariable<bool> Ridden = new NetworkVariable<bool>();
        HorseActor _horse;

        void Awake() { _horse = GetComponent<HorseActor>(); }

        public override void OnNetworkSpawn()
        {
            _horse.Build(IsServer);
            if (!IsServer) UnityEngine.Debug.Log("[лошадь] у себя");
        }

        void Update()
        {
            if (!IsSpawned) return;
            if (IsServer) Ridden.Value = _horse.Ridden;
            else if (_horse.Ridden != Ridden.Value) _horse.Show(Ridden.Value);
        }
    }
}
