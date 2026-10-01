// Сетевая половина постройки: вид, сторона, ход стройки, ступень, прочность —
// пишет хост, клиенты показывают. Вид и сторона едут при спавне: клиент по ним
// собирает ту же коробку (BuildingActor.Init).
using DjvaGoda.Core;
using Unity.Netcode;

namespace DjvaGoda.Game
{
    [UnityEngine.RequireComponent(typeof(BuildingActor))]
    public class BuildingNet : NetworkBehaviour
    {
        public readonly NetworkVariable<int> Kind = new NetworkVariable<int>();
        public readonly NetworkVariable<int> Side = new NetworkVariable<int>();
        public readonly NetworkVariable<float> Progress = new NetworkVariable<float>();
        public readonly NetworkVariable<int> Grade = new NetworkVariable<int>();
        public readonly NetworkVariable<float> Health = new NetworkVariable<float>();

        BuildingActor _actor;

        void Awake() { _actor = GetComponent<BuildingActor>(); }

        public override void OnNetworkSpawn()
        {
            if (IsServer)
            {
                Kind.Value = (int)_actor.State.Kind;
                Side.Value = (int)_actor.State.Side;
                Write();
                return;
            }
            _actor.Init((BuildingKind)Kind.Value, (Faction)Side.Value, false);
            Read();
            UnityEngine.Debug.Log("[стройка] у себя: " + _actor.name + ", готово " + (int)(Progress.Value * 100) + "%");
        }

        void Update()
        {
            if (!IsSpawned || _actor.State == null) return;
            if (IsServer) Write();
            else Read();
        }

        void Write()
        {
            Side.Value = (int)_actor.State.Side;
            Progress.Value = _actor.State.Progress;
            Grade.Value = _actor.State.Grade;
            Health.Value = _actor.State.Health;
        }

        void Read()
        {
            // Сторона меняется однажды — стража уходит к злодею со взятием дворца.
            _actor.State.Side = (Faction)Side.Value;
            _actor.Side = Side.Value;
            _actor.State.Progress = Progress.Value;
            _actor.State.Grade = Grade.Value;
            _actor.State.Health = Health.Value;
        }
    }
}
