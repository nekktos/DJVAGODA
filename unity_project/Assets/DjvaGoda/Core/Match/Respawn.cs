// Где и когда персонаж встаёт после смерти (перенос world.gd, player.gd).
//
// Эльф возрождается у ближайшего ДОСТРОЕННОГО дома (GDD 9a: дома — места
// возрождения). Домов нет — ждёт, пока живые отстроят; некого ждать, когда
// эльфы выбыли. Здоровье возвращается, ранения — нет (GDD 4.1). Вожак
// падает окончательно и досматривает партию наблюдателем.
using System;
using System.Collections.Generic;

namespace DjvaGoda.Core
{
    public enum RespawnVerdict { Now, WaitForHouse, Never }

    public static class Respawn
    {
        public const float Delay = 5f;
        /// Как часто павший эльф проверяет, не отстроили ли дом.
        public const float HouseRetry = 2f;
        /// Сколько мест в ряду точки появления; шаг — 3 м у спавна, 2 м у дома.
        public const int SlotRow = 6;
        public const float SlotStep = 3f;
        public const float HouseSlotStep = 2f;

        /// Стартовые дома эльфов: три в кольце поселения.
        public static readonly V3[] ElfHousesStart =
        {
            MapLayout.ElvesCentre + new V3(45f, 0f, 0f),
            MapLayout.ElvesCentre + new V3(-40.4f, 0f, -19.7f),
            MapLayout.ElvesCentre + new V3(-10f, 0f, 43.9f),
        };

        /// Сколько домов могут держать эльфы: пять на игрока, не меньше чем на одного
        /// (за пустую сторону держит ИИ).
        public static int ElfHouseLimit(int elfPlayers)
        {
            return Res.ElfHousesPerPlayer * Math.Max(1, elfPlayers);
        }

        public static RespawnVerdict Verdict(Faction side, bool leader, int elfHousesDone, bool elvesOut)
        {
            if (leader) return RespawnVerdict.Never;
            if (side != Faction.Elves) return RespawnVerdict.Now;
            if (elfHousesDone > 0) return RespawnVerdict.Now;
            return elvesOut ? RespawnVerdict.Never : RespawnVerdict.WaitForHouse;
        }

        /// Точка у ближайшего достроенного дома — с северной стороны: персонаж
        /// встаёт лицом на север и с юга смотрел бы в стену своего дома.
        public static V3? ElfHousePoint(V3 near, IEnumerable<V3> doneHouses)
        {
            V3? best = null;
            float bestDistance = float.MaxValue;
            foreach (var house in doneHouses)
            {
                float d = near.Distance(house);
                if (d < bestDistance)
                {
                    bestDistance = d;
                    best = house;
                }
            }
            if (!best.HasValue) return null;
            float back = Res.BuildingSize(BuildingKind.ElfHouse).Z * 0.5f + 3f;
            return best.Value + new V3(0f, 1f, back);
        }

        /// Где появиться: в партию — у точки стороны, эльфу после смерти — у дома.
        public static V3 SpawnPoint(Faction side, int slot, bool respawn, V3 near, IEnumerable<V3> doneElfHouses)
        {
            if (respawn && side == Faction.Elves)
            {
                var house = ElfHousePoint(near, doneElfHouses);
                if (house.HasValue) return house.Value + new V3((slot % SlotRow) * HouseSlotStep, 0f, 0f);
            }
            return Factions.Spawn[(int)side] + new V3((slot % SlotRow) * SlotStep, 0f, 0f);
        }
    }
}
