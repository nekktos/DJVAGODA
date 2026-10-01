// Обоз: скорость от лошадей, груз, что с ним можно сделать (перенос caravan.gd).
//
// Езда, объезд построек, путь по сетке — Unity-слой; здесь правила.
namespace DjvaGoda.CoreOld
{
    public enum CaravanState { ToMine, Loading, ToHome, Unloading, Finished }

    public enum CaravanAction { None, Intercept, Rob, Plunder }

    public static class CaravanRules
    {
        public const float Speed = 8f;
        public const int HorsesMin = 1;
        public const int HorsesMax = 6;
        public const float HorseSpeedStep = 0.4f;
        public const float HorseHealth = 60f;
        /// Обоз встаёт, когда рядом враг.
        public const float HaltRange = 18f;
        public const float BuildingClearance = 6f;
        public const float MaxHealth = 220f;
        public const int Capacity = 120;
        public const float LoadSeconds = 3f;
        public const float WaypointReach = 3f;
        public const float DockRange = 14f;
        /// Грузится, только если конец маршрута не дальше этого от входа шахты.
        public const float LoadReach = 45f;
        public const float GuardLeash = 16f;
        /// Полный склад: обоз ждёт рядом и пробует снова раз в столько секунд.
        public const float WaitRetry = 3f;

        /// Без лошадей не едет; каждая лошадь сверх первой прибавляет скорость.
        public static float SpeedFor(int horses)
        {
            if (horses <= 0) return 0f;
            return Speed * (1f + HorseSpeedStep * (horses - 1));
        }

        /// Соперники по хозяйству: злодей и стража — у обоих склады и обозы.
        public static bool Rivals(Faction a, Faction b)
        {
            return a != b && a != Faction.Elves && b != Faction.Elves;
        }

        /// Что сторона может сделать со стоящим чужим обозом, подойдя вплотную.
        /// Одно правило для игрока, подсказки и хоста.
        /// Перехват — сопернику со своим складом (гнать есть куда); увести
        /// лошадей — эльфам и тем, кому гнать некуда; разграбить — повозку без лошадей.
        public static CaravanAction ActionFor(Faction actor, Faction cartSide, int horses, bool stopped,
            int cargoTotal, bool actorHasStorage)
        {
            if (actor == cartSide || !stopped) return CaravanAction.None;
            if (horses > 0)
            {
                if (Rivals(actor, cartSide) && actorHasStorage) return CaravanAction.Intercept;
                return CaravanAction.Rob;
            }
            if (cargoTotal > 0) return CaravanAction.Plunder;
            return CaravanAction.None;
        }

        /// Выгрузить в склад сколько влезет; возвращает, всё ли выгружено.
        /// Невлезшее остаётся в обозе — он ждёт у полного склада.
        public static bool Unload(int[] cargo, Wallet wallet)
        {
            bool all = true;
            for (int i = 0; i < Res.Count; i++)
            {
                if (cargo[i] <= 0) continue;
                int placed = wallet.AddStored(i, cargo[i]);
                cargo[i] -= placed;
                if (cargo[i] > 0) all = false;
            }
            return all;
        }
    }
}
