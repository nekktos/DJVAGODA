// Что можно добывать: дерево плана, камень, золото. У деревьев леса — номер.
// Стоит в сцене (мир собирается в редакторе), поля сохраняются вместе с ней.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class Harvestable : MonoBehaviour
    {
        /// Все стоящие источники: батраки ищут по списку, а не по сцене каждый кадр.
        public static readonly List<Harvestable> All = new List<Harvestable>();
        static int _nextId = 1;
        /// Свой номер: GetInstanceID в Unity 6.6 устарел.
        public int Id { get; private set; }

        public ResourceKind Resource;
        public int HitsLeft;
        /// Номер дерева леса эльфов; −1 — не из леса.
        public int TreeIndex = -1;
        /// Номер источника, одинаковый на всех машинах: дерево леса — его номер,
        /// прочее — PlanBase + номер части плана. По нему хост сообщает «исчерпан».
        public int Key = -1;
        public const int PlanBase = 100000;

        static readonly Dictionary<int, Harvestable> ByKey = new Dictionary<int, Harvestable>();

        public static Harvestable Find(int key)
        {
            Harvestable found;
            return ByKey.TryGetValue(key, out found) && found != null ? found : null;
        }

        /// Удар по источнику (у хоста) — игроком или батраком, счётчик один:
        /// у дерева леса — в лесу ядра, у прочих — здесь. true — исчерпан и
        /// убран у всех (MatchNet).
        public bool TakeHit()
        {
            bool gone;
            if (TreeIndex >= 0)
            {
                var world = Object.FindAnyObjectByType<World>();
                gone = world == null || world.Forest.Hit(TreeIndex) <= 0;
            }
            else
            {
                HitsLeft--;
                gone = HitsLeft <= 0;
            }
            // Удар слышен и виден всем: стук и щепки цветом ресурса.
            MatchNet.Chips(transform.position + Vector3.up * (TreeIndex >= 0 ? 1.2f : 0.8f), (int)Resource);
            if (gone) MatchNet.Deplete(Key);
            return gone;
        }

        void OnEnable()
        {
            if (Id == 0) Id = _nextId++;
            All.Add(this);
            if (Key >= 0) ByKey[Key] = this;
        }
        void OnDisable()
        {
            All.Remove(this);
            Harvestable mine;
            if (Key >= 0 && ByKey.TryGetValue(Key, out mine) && mine == this) ByKey.Remove(Key);
        }
    }
}
