// Трупы (перенос combat/corpse.gd): по GDD, раздел 3, павший остаётся лежать
// в мире, а не исчезает. Только вид: без коллизии (живые не застревают в
// телах), без сети как объекта — хост рассылает «здесь лёг такой-то»
// (MatchNet.CorpseRpc), каждый пир кладёт фигуру у себя. Отрубленное при
// жизни у трупа тоже отсутствует. Не больше 30: самые старые убираются.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public static class Corpses
    {
        public const int Limit = 30;
        /// Вид «вожак стороны» — сверх ролей батраков и бойцов (AgentRole).
        public const int HeroLook = 9;

        static readonly Queue<GameObject> Lying = new Queue<GameObject>();

        public static int Count
        {
            get
            {
                int n = 0;
                foreach (var go in Lying) if (go != null) n++;
                return n;
            }
        }

        /// Хост: павший лёг — у всех.
        public static void Spawn(Vector3 at, float yaw, int look, int side, int severed)
        {
            var net = MatchNet.Instance;
            if (net != null && net.IsSpawned) net.CorpseRpc(at, yaw, look, side, severed);
            else Place(at, yaw, look, side, severed);
        }

        public static void Place(Vector3 at, float yaw, int look, int side, int severed)
        {
            // Белок не кладём: стая гибнет десятками, а тушка размером с ладонь.
            if (look == (int)AgentRole.Beast) return;
            var root = new GameObject("Труп").transform;
            root.position = at;
            root.rotation = Quaternion.Euler(0f, yaw, 0f);
            var figureLook = look == HeroLook ? FigureLook.Hero((Faction)side) : FigureLook.Agent((AgentRole)look, (Faction)side);
            Figure.Build(root, figureLook).Lay(severed);
            Lying.Enqueue(root.gameObject);
            while (Lying.Count > Limit)
            {
                var oldest = Lying.Dequeue();
                if (oldest != null) Object.Destroy(oldest);
            }
        }
    }
}
