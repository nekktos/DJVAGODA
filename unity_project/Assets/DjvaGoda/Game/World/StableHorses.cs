// Лошади в загоне конюшни — столько, сколько у стороны свободных (до четырёх
// на виду). Купил лошадь — она появилась в загоне; ушла в упряжку обоза или
// под седло — загон опустел (playtest-10: «купил лошадь — ничего не дало»).
// Только вид: число берётся из казны, которая и так едет по сети.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class StableHorses : MonoBehaviour
    {
        public const int Shown = 4;
        public Faction Side;
        public Vector3 Paddock;
        public float Width;

        readonly List<Beast> _horses = new List<Beast>();

        void Update()
        {
            int want = Mathf.Min(Shown, Treasury.Of(Side).HorsesFree);
            while (_horses.Count < want)
            {
                int i = _horses.Count;
                var horse = Beast.Horse(transform);
                horse.transform.localPosition = Paddock + new Vector3((i - 1.5f) * Width * 0.22f, 0f, (i % 2 == 0 ? -1f : 1f) * 1.2f);
                horse.transform.localRotation = Quaternion.Euler(0f, 60f + i * 47f, 0f);
                _horses.Add(horse);
            }
            while (_horses.Count > want)
            {
                var last = _horses[_horses.Count - 1];
                _horses.RemoveAt(_horses.Count - 1);
                if (last != null) Destroy(last.gameObject);
            }
        }
    }
}
