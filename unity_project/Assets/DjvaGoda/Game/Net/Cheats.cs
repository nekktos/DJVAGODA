// Команды для плейтеста (перенос cheats.gd). Только в отладочной сборке и в
// редакторе. Выполняет хост — по той же причине, что и всё остальное: выданное
// у клиента затёрла бы синхронизация. Клиент шлёт строку (NetPlayer.CheatRpc),
// ответ уходит обратно ему (NetPlayer.CheatReplyRpc).
using System.Collections.Generic;
using System.Globalization;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public static class Cheats
    {
        public const string Help =
            "res <дер> <кам> <зол> <жел> [еда] [уголь] — выдать; res all <n> — всего по n\n" +
            "xp <n> — опыт   heal — вылечить всё   bandages <n> — бинты\n" +
            "hurt <зона> <урон> — head torso arm_l arm_r leg_l leg_r   limb <зона> — оторвать\n" +
            "tp <x> <z> — телепорт   goto villain|elves|guard|bench|mine|trader\n" +
            "kill — умереть   who — кто в партии   help — этот список";

        /// Можно ли вообще: отладочная сборка или редактор.
        public static bool Allowed { get { return Debug.isDebugBuild || Application.isEditor; } }

        /// Выполнить у хоста команду игрока me; вернуть ответ.
        public static string Run(PlayerCharacter me, string line)
        {
            if (!Allowed) return "команды только в отладочной сборке";
            if (me == null) return "нет персонажа";
            var words = (line ?? "").Trim().ToLowerInvariant().Split(new[] { ' ' }, System.StringSplitOptions.RemoveEmptyEntries);
            if (words.Length == 0) return "";
            Debug.Log("[чит] " + me.name + ": " + line);
            switch (words[0])
            {
                case "help": return Help;
                case "res": return Resources(me, words);
                case "xp":
                    me.Vitals.Experience += Int(words, 1, 1000);
                    return "опыт: " + me.Vitals.Experience;
                case "heal":
                    me.Vitals.Revive();
                    me.Vitals.Health = me.Vitals.MaxHealth;
                    me.Body.SeveredMask = 0;
                    me.Body.CrippledMask = 0;
                    me.Body.Bleeding = false;
                    me.Body.EyesLost = 0;
                    return "здоров";
                case "bandages":
                    me.Body.Bandages = Int(words, 1, 5);
                    return "бинтов: " + me.Body.Bandages;
                case "hurt":
                    if (words.Length < 2) return "hurt <зона> <урон>";
                    Actor.Strike(me, Int(words, 2, 30), words[1], WeaponKind.Sword, false, null);
                    return "удар в " + words[1] + ", здоровье " + Mathf.RoundToInt(me.Vitals.Health);
                case "limb":
                {
                    int index = words.Length > 1 ? System.Array.IndexOf(BodyState.LimbKeys, words[1]) : -1;
                    if (index < 0) return "limb arm_l|arm_r|leg_l|leg_r";
                    me.Body.SeveredMask |= 1 << index;
                    Pickup.DropLimb(me.Feet + new V3(0.8f, 0.2f, 0f), (Limb)index);
                    return "оторвано: " + words[1];
                }
                case "tp":
                    if (words.Length < 3) return "tp <x> <z>";
                    return Move(me, new V3(Float(words[1]), 0f, Float(words[2])));
                case "goto": return Goto(me, words.Length > 1 ? words[1] : "");
                case "kill":
                    Actor.Strike(me, 100000f, "torso", WeaponKind.Sword, false, null);
                    return "убит";
                case "who": return Who();
                default: return "нет такой команды: " + words[0] + " (help — список)";
            }
        }

        static string Resources(PlayerCharacter me, string[] words)
        {
            var add = new int[Res.Count];
            if (words.Length > 1 && words[1] == "all")
                for (int i = 0; i < Res.Count; i++) add[i] = Int(words, 2, 100);
            else
                for (int i = 0; i < Res.Count; i++) add[i] = Int(words, i + 1, 0);
            var wallet = Treasury.Of(me.Faction);
            int most = 0;
            for (int i = 0; i < Res.Count; i++) most = Mathf.Max(most, wallet.Carried.GetAmount((ResourceKind)i) + add[i]);
            wallet.Carried.Capacity = Mathf.Max(wallet.Carried.Capacity, most);
            for (int i = 0; i < Res.Count; i++) if (add[i] > 0) wallet.Add(i, add[i]);
            var have = new List<string>();
            for (int i = 0; i < Res.Count; i++) have.Add(wallet.GetAmount(i).ToString());
            return "казна стороны: " + string.Join(", ", have.ToArray());
        }

        static string Goto(PlayerCharacter me, string place)
        {
            switch (place)
            {
                case "villain": return Move(me, Factions.Spawn[(int)Faction.Villain]);
                case "elves": return Move(me, Factions.Spawn[(int)Faction.Elves]);
                case "guard": case "palace": return Move(me, Factions.Spawn[(int)Faction.Guard]);
                case "bench": return Move(me, MapLayout.Workbench + new V3(3f, 0f, 0f));
                case "mine": return Move(me, MapLayout.MicroMine + new V3(0f, 0f, 6f));
                case "trader": return Move(me, MapLayout.Traders[(int)me.Faction] + new V3(3f, 0f, 0f));
                default: return "goto villain|elves|guard|bench|mine|trader";
            }
        }

        static string Move(PlayerCharacter me, V3 at)
        {
            RaycastHit hit;
            var top = new Vector3(at.X, 200f, at.Z);
            var ground = Physics.Raycast(top, Vector3.down, out hit, 400f, HitZone.WorldMask, QueryTriggerInteraction.Ignore)
                ? hit.point : new Vector3(at.X, at.Y, at.Z);
            me.Teleport(ground + Vector3.up * 0.1f);
            return "здесь: " + Mathf.Round(ground.x) + ", " + Mathf.Round(ground.z);
        }

        static string Who()
        {
            var lines = new List<string>();
            foreach (var actor in Actor.All)
            {
                var player = actor as PlayerCharacter;
                if (player == null) continue;
                lines.Add(player.name + " — " + Factions.Names[(int)player.Faction] + (player.Alive ? "" : " (пал)")
                    + (player.GetComponent<HeroDriver>() != null ? " [ИИ]" : ""));
            }
            return string.Join("\n", lines.ToArray());
        }

        static int Int(string[] words, int index, int fallback)
        {
            int value;
            return index < words.Length && int.TryParse(words[index], out value) ? value : fallback;
        }

        static float Float(string word)
        {
            float value;
            return float.TryParse(word, NumberStyles.Float, CultureInfo.InvariantCulture, out value) ? value : 0f;
        }
    }
}
