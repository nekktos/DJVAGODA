// Сетевая половина того, что лежит на земле: вид (куча, рука, нога). Лежит на
// месте спавна; что внутри кучи — знает только хост.
using Unity.Netcode;

namespace DjvaGoda.Game
{
    public class PickupNet : NetworkBehaviour
    {
        public readonly NetworkVariable<int> Kind = new NetworkVariable<int>();
        [System.NonSerialized] public PickupKind AssignedKind;

        public override void OnNetworkSpawn()
        {
            if (IsServer) Kind.Value = (int)AssignedKind;
            Pickup.Build(transform, (PickupKind)Kind.Value);
            var pickup = GetComponent<Pickup>();
            if (pickup != null) pickup.Kind = (PickupKind)Kind.Value;
        }
    }
}
