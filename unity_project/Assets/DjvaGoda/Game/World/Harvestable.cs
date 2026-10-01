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

        void OnEnable()
        {
            if (Id == 0) Id = _nextId++;
            All.Add(this);
        }
        void OnDisable() { All.Remove(this); }
    }
}
