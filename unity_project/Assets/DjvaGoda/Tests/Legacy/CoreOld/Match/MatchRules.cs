// Исход партии: захват дворца, выбывание сторон, победа (перенос objective.gd).
//
// ПАРТИЯ ИДЁТ ДО ПОСЛЕДНЕЙ СТОРОНЫ (GDD 9a). Ядро не спрашивает мир само —
// мир собирает по стороне снимок (SideSnapshot), ядро решает и возвращает
// объявления. Считает только хост; клиенты получают итог.
using System.Collections.Generic;

namespace DjvaGoda.CoreOld
{
    /// Что мир знает о стороне в этот миг — ровно то, что нужно правилам.
    public struct SideSnapshot
    {
        public bool HasPlayers;
        /// Есть ли у пустой стороны ИИ-вожак и жив ли он.
        public bool AiHeroExists;
        public bool AiHeroAlive;
        /// Живые казармы (и недостроенные).
        public bool HasBarracks;
        /// Эльфы: дома (и строящиеся) и живые эльфы.
        public int ElfHouses;
        public int LivingElves;
    }

    public class MatchState
    {
        public static readonly V3 Palace = new V3(300f, 6f, -300f);
        public const float CaptureRadius = 34f;
        public const float CaptureSeconds = 20f;
        public const float DecayPerSecond = 0.06f;
        public const float CheckInterval = 2f;

        public static readonly string[] VictoryText =
        {
            "дворец взят, эльфы вырезаны",
            "древние земли вернулись к эльфам",
            "злодей и эльфы уничтожены",
        };
        public static readonly string[] OutText = { "вожак злодея пал", "эльфов больше нет", "стража сломлена" };

        public Faction PalaceOwner = Faction.Guard;
        public float CaptureProgress;
        public bool Contested;
        public int Claimant = -1;
        public readonly bool[] LeaderDown = new bool[Factions.Count];
        public readonly bool[] Out = new bool[Factions.Count];
        public readonly bool[] Victors = new bool[Factions.Count];
        public bool GuardAbsorbed;

        /// Союз стражи со злодеем после взятия дворца — на каждом пире.
        public void ApplyAlliances()
        {
            Factions.Overlord[(int)Faction.Guard] = GuardAbsorbed ? (int)Faction.Villain : -1;
        }

        /// Такт захвата: кто из сторон стоит в круге. Возвращает объявления.
        public List<string> TickCapture(float delta, IList<Faction> present)
        {
            var said = new List<string>();
            Contested = present.Count > 1;
            if (present.Count == 0 || Contested)
            {
                Claimant = -1;
                CaptureProgress = System.Math.Max(0f, CaptureProgress - DecayPerSecond * delta);
                return said;
            }
            var who = present[0];
            if (who == PalaceOwner)
            {
                Claimant = -1;
                CaptureProgress = System.Math.Max(0f, CaptureProgress - DecayPerSecond * delta * 4f);
                return said;
            }
            if (Claimant != (int)who)
            {
                Claimant = (int)who;
                CaptureProgress = 0f;
            }
            CaptureProgress = System.Math.Min(1f, CaptureProgress + delta / CaptureSeconds);
            if (CaptureProgress >= 1f) said.AddRange(Capture(who));
            return said;
        }

        /// Дворец взят. Злодей получает земли людей и стражу — однажды.
        List<string> Capture(Faction faction)
        {
            var said = new List<string>();
            PalaceOwner = faction;
            CaptureProgress = 0f;
            Claimant = -1;
            said.Add("Дворец захвачен: " + Factions.NameOf(faction));
            if (faction == Faction.Villain && !GuardAbsorbed)
            {
                GuardAbsorbed = true;
                ApplyAlliances();
                said.Add("Земли людей и стража теперь под рукой злодея");
            }
            return said;
        }

        public string ReportLeaderDown(Faction faction, int killerFaction)
        {
            if (LeaderDown[(int)faction]) return null;
            LeaderDown[(int)faction] = true;
            string text = Factions.NameOf(faction) + ": вожак пал";
            if (killerFaction >= 0) text += " (" + Factions.Names[killerFaction] + ")";
            return text;
        }

        /// Сломлена ли сторона. Страже мало павшего командира — нужны и
        /// снесённые казармы. Пустая сторона без ИИ-вожака ещё НЕ сломлена: он
        /// появляется не в первый кадр.
        public bool Broken(Faction faction, SideSnapshot side)
        {
            if (!side.HasPlayers && side.AiHeroExists && !side.AiHeroAlive) return true;
            if (!LeaderDown[(int)faction]) return false;
            if (faction == Faction.Guard) return !side.HasBarracks;
            return true;
        }

        /// Выбыла ли сторона: эльфы — нет домов И нет живых (ответ автора);
        /// стража — перешла к злодею или сломлена; злодей — сломлен.
        public bool SideOut(Faction faction, SideSnapshot side)
        {
            if (faction == Faction.Guard && GuardAbsorbed) return true;
            if (faction == Faction.Elves) return side.ElfHouses == 0 && side.LivingElves == 0;
            return Broken(faction, side);
        }

        /// Пересмотреть выбывших; одна осталась — победа. Возвращает объявления.
        public List<string> CheckVictories(SideSnapshot[] sides)
        {
            var said = new List<string>();
            for (int f = 0; f < Factions.Count; f++)
            {
                var faction = (Faction)f;
                if (Out[f] || !SideOut(faction, sides[f])) continue;
                Out[f] = true;
                if (faction == Faction.Guard && GuardAbsorbed)
                    said.Add(Factions.NameOf(faction) + " больше не сторона: она служит злодею");
                else
                    said.Add(Factions.NameOf(faction) + " выбывает из партии: " + OutText[f]);
            }
            int left = -1;
            int count = 0;
            for (int f = 0; f < Factions.Count; f++)
            {
                if (Out[f]) continue;
                count++;
                left = f;
            }
            if (count == 1 && !Victors[left])
            {
                Victors[left] = true;
                said.Add("ПОБЕДА: " + Factions.Names[left] + " — " + VictoryText[left]);
            }
            return said;
        }

        public int SidesLeft()
        {
            int count = 0;
            for (int f = 0; f < Factions.Count; f++) if (!Out[f]) count++;
            return count;
        }
    }
}
