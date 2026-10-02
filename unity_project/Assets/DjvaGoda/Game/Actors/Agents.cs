// Батраки, бойцы, волки — появление и уход одним входом.
//
// По сети это префаб Resources/Agent (NetworkObject, NetworkTransform хоста,
// AgentNet): ходит и думает он ТОЛЬКО у хоста — мозг (UnitAgent или
// LabourerAgent) хост добавляет себе сам, а клиентам едут положение, роль и
// сторона, и они рисуют тот же вид (AgentBody). Без сети — простой объект.
using DjvaGoda.Core;
using Unity.Netcode;
using UnityEngine;

namespace DjvaGoda.Game
{
    public enum AgentRole { Labourer, Swordsman, Archer, Champion, Beast }

    public static class Agents
    {
        static GameObject _prefab;

        public static AgentRole RoleOf(UnitKind kind)
        {
            switch (kind)
            {
                case UnitKind.Archer: return AgentRole.Archer;
                case UnitKind.Champion: return AgentRole.Champion;
                case UnitKind.Beast: return AgentRole.Beast;
            }
            return AgentRole.Swordsman;
        }

        static bool Networked
        {
            get
            {
                var net = NetworkManager.Singleton;
                return net != null && net.IsListening && net.IsServer;
            }
        }

        /// Создать тело на месте (у хоста). Мозг добавляет вызывающий — до Show.
        public static GameObject Make(AgentRole role, Faction side, V3 at, string name)
        {
            GameObject go;
            if (Networked)
            {
                if (_prefab == null) _prefab = Resources.Load<GameObject>("Agent");
                go = Object.Instantiate(_prefab, at.ToUnity(), Quaternion.identity);
                var net = go.GetComponent<AgentNet>();
                net.AssignedRole = role;
                net.AssignedSide = side;
            }
            else
            {
                go = new GameObject();
                go.transform.position = at.ToUnity();
                AgentBody.Build(go.transform, role, side);
            }
            go.name = name;
            return go;
        }

        /// Выпустить в мир: по сети — заспавнить (мозг уже добавлен).
        public static void Show(GameObject go)
        {
            var net = go.GetComponent<NetworkObject>();
            if (net != null && Networked) net.Spawn();
        }

        /// Батраки стороны по делам — на любой машине: у хоста по мозгам, у
        /// клиента по сетевым переменным. Возвращает число батраков.
        public static int CountCrew(Faction side, int[] byRole)
        {
            int crew = 0;
            foreach (var net in Object.FindObjectsByType<AgentNet>(FindObjectsSortMode.None))
            {
                if (!net.IsSpawned || net.Role.Value != (int)AgentRole.Labourer || net.Side.Value != (int)side) continue;
                byRole[net.Job.Value]++;
                crew++;
            }
            if (crew > 0) return crew;
            foreach (var actor in Actor.All)
            {
                var worker = actor as LabourerAgent;
                if (worker == null || worker.Brain == null || worker.Brain.Side != side) continue;
                byRole[(int)worker.Brain.Role]++;
                crew++;
            }
            return crew;
        }

        /// Убрать (смерть, конец срока): по сети — у всех.
        public static void Remove(GameObject go)
        {
            if (go == null) return;
            var net = go.GetComponent<NetworkObject>();
            if (net != null && net.IsSpawned) net.Despawn(true);
            else Object.Destroy(go);
        }
    }

    /// Вид батрака, бойца, распорядителя — фигура (Figure) по роли и стороне,
    /// с орудием в руке; зверь призыва — волк (Beast).
    public static class AgentBody
    {
        public static void Build(Transform root, AgentRole role, Faction side)
        {
            if (role == AgentRole.Beast)
            {
                Beast.Wolf(root).name = "Тело";
                return;
            }
            var figure = Figure.Build(root, FigureLook.Agent(role, side));
            WeaponKind tool;
            switch (role)
            {
                case AgentRole.Archer: tool = WeaponKind.Bow; break;
                case AgentRole.Labourer: tool = WeaponKind.Axe; break;
                default: tool = WeaponKind.Sword; break;
            }
            WeaponView.Hold(WeaponShapes.Build(tool), figure.HandR, tool);
        }
    }
}
