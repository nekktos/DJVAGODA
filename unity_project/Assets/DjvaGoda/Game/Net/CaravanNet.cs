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
        /// Чей рейс, что делает, сколько метров осталось — для окна склада у владельца.
        public readonly NetworkVariable<int> Owner = new NetworkVariable<int>();
        public readonly NetworkVariable<int> State = new NetworkVariable<int>();
        public readonly NetworkVariable<float> Left = new NetworkVariable<float>();
        [System.NonSerialized] public Faction AssignedSide;

        CaravanActor _cart;
        float _leftT;

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
                Owner.Value = _cart.Trip.Owner;
                State.Value = (int)_cart.Trip.State;
                // Длина пути — не каждый кадр: на глаз цифра меняется раз в секунды.
                _leftT -= UnityEngine.Time.deltaTime;
                if (_leftT <= 0f)
                {
                    _leftT = 0.5f;
                    Left.Value = _cart.LeftNow;
                }
                return;
            }
            _cart.Side = Side.Value;
            _cart.ShownHorses = Horses.Value;
            _cart.ShownHalted = Halted.Value;
            _cart.ShownCargo = Cargo.Value;
            _cart.ShownOwner = Owner.Value;
            _cart.ShownState = State.Value;
            _cart.ShownLeft = Left.Value;
            CaravanActor.ShowHarness(transform, Horses.Value);
        }
    }
}
