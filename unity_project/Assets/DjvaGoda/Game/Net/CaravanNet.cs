// Сетевая половина обоза: сторона, упряжка, стоит ли, сколько груза
// (положение и поворот везёт NetworkTransform хоста). Рейс считает только
// хост; клиентам — чтобы рисовать телегу и подсказывать, что с ней сделать
// (увести лошадей, перехватить, разграбить). Сторона меняется при перехвате.
using DjvaGoda.Core;
using Unity.Netcode;

namespace DjvaGoda.Game
{
    public class CaravanNet : NetworkBehaviour
    {
        public readonly NetworkVariable<int> Side = new NetworkVariable<int>();
        public readonly NetworkVariable<int> Horses = new NetworkVariable<int>();
        public readonly NetworkVariable<bool> Halted = new NetworkVariable<bool>();
        public readonly NetworkVariable<int> Cargo = new NetworkVariable<int>();
        [System.NonSerialized] public Faction AssignedSide;

        CaravanActor _cart;

        public override void OnNetworkSpawn()
        {
            _cart = GetComponent<CaravanActor>();
            if (IsServer) Side.Value = (int)AssignedSide;
            // У хоста — с зонами попадания (бьют его обоз), у клиентов — только вид.
            CaravanActor.Build(transform, (Faction)Side.Value, IsServer ? _cart : null);
            if (!IsServer) UnityEngine.Debug.Log("[обоз] у себя: обоз стороны " + Factions.Names[Side.Value]);
        }

        void Update()
        {
            if (!IsSpawned || _cart == null) return;
            if (IsServer)
            {
                if (_cart.Trip == null) return;
                Side.Value = _cart.Side;
                Horses.Value = _cart.Trip.Horses;
                Halted.Value = _cart.Trip.Halted;
                Cargo.Value = _cart.Trip.CargoTotal;
                return;
            }
            _cart.Side = Side.Value;
            _cart.ShownHorses = Horses.Value;
            _cart.ShownHalted = Halted.Value;
            _cart.ShownCargo = Cargo.Value;
        }
    }
}
