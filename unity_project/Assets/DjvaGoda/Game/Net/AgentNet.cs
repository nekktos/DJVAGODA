// Сетевая половина батрака, бойца, белки: роль и сторона (положение везёт
// NetworkTransform хоста). Мозг — только у хоста; клиенты рисуют вид.
using DjvaGoda.Core;
using Unity.Netcode;

namespace DjvaGoda.Game
{
    public class AgentNet : NetworkBehaviour
    {
        public readonly NetworkVariable<int> Role = new NetworkVariable<int>();
        public readonly NetworkVariable<int> Side = new NetworkVariable<int>();
        /// Дело батрака (LabourerRole) — для экрана хозяйства у клиентов.
        public readonly NetworkVariable<int> Job = new NetworkVariable<int>();

        [System.NonSerialized] public AgentRole AssignedRole;
        [System.NonSerialized] public Faction AssignedSide;

        public override void OnNetworkSpawn()
        {
            if (IsServer)
            {
                Role.Value = (int)AssignedRole;
                Side.Value = (int)AssignedSide;
            }
            AgentBody.Build(transform, (AgentRole)Role.Value, (Faction)Side.Value);
            if (!IsServer) UnityEngine.Debug.Log("[хозяйство] у себя: " + (AgentRole)Role.Value + " стороны " + Factions.Names[Side.Value]);
        }

        LabourerAgent _worker;

        void Update()
        {
            if (!IsSpawned || !IsServer) return;
            if (_worker == null) _worker = GetComponent<LabourerAgent>();
            if (_worker != null && _worker.Brain != null) Job.Value = (int)_worker.Brain.Role;
        }
    }
}
