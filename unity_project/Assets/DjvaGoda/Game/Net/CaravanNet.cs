// Сетевая половина обоза: сторона (положение и поворот везёт NetworkTransform
// хоста). Рейс считает только хост; клиенты рисуют телегу.
using DjvaGoda.Core;
using Unity.Netcode;

namespace DjvaGoda.Game
{
    public class CaravanNet : NetworkBehaviour
    {
        public readonly NetworkVariable<int> Side = new NetworkVariable<int>();
        [System.NonSerialized] public Faction AssignedSide;

        public override void OnNetworkSpawn()
        {
            if (IsServer) Side.Value = (int)AssignedSide;
            // У хоста — с зонами попадания (бьют его обоз), у клиентов — только вид.
            CaravanActor.Build(transform, (Faction)Side.Value, IsServer ? GetComponent<CaravanActor>() : null);
            if (!IsServer) UnityEngine.Debug.Log("[обоз] у себя: обоз стороны " + Factions.Names[Side.Value]);
        }
    }
}
