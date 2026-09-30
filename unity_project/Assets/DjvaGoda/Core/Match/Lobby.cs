// Кто куда встаёт при входе в сессию (перенос world.gd::_spawn_player,
// network_manager.gd::max_clients).
//
// Мест на сторонах: злодей — 1, эльфы — 5, стража — 5. Просил занятую —
// встаёт на первую свободную и слышит об этом. Номер места разводит точки
// появления и трупы; вожак — тот, кто встал за злодея.
using System.Collections.Generic;

namespace DjvaGoda.Core
{
    public static class Lobby
    {
        public const int DefaultPort = 24545;
        public const float ConnectTimeout = 8f;

        public static int TotalSlots()
        {
            int sum = 0;
            foreach (int n in Factions.Slots) sum += n;
            return sum;
        }

        /// Сколько клиентов принимает хост (сам хост — одно из мест).
        public static int MaxClients() { return TotalSlots() - 1; }

        /// Сторона для входящего: просимая, если там есть место, иначе первая
        /// свободная; -1 — мест нет нигде. humans[f] — живых людей на стороне
        /// (герой ИИ не занимает места).
        public static int AssignFaction(int wanted, int[] humans)
        {
            if (wanted >= 0 && wanted < Factions.Count && humans[wanted] < Factions.Slots[wanted]) return wanted;
            for (int f = 0; f < Factions.Count; f++)
                if (humans[f] < Factions.Slots[f]) return f;
            return -1;
        }

        /// Свободный номер места; -1 — сессия заполнена.
        public static int NextFreeSlot(ICollection<int> used)
        {
            for (int i = 0; i < TotalSlots() + Factions.Count; i++)
                if (!used.Contains(i)) return i;
            return -1;
        }

        public static string Redirected(int asked, int given)
        {
            return "Сторона «" + Factions.Names[asked] + "» занята — вы играете за «" + Factions.Names[given] + "».";
        }
    }
}
