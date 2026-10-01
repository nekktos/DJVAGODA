// Приказы командира стражи и задания старейшины эльфов (перенос orders.gd и
// elf_tasks.gd). Приказы собраны из уже работающих механик, а не из новых;
// награда — та же валюта, что в лавке.
namespace DjvaGoda.CoreOld
{
    /// Новые — только в конец: номер уходит в сеть и в сохранение.
    public enum OrderKind { Hold, Slay, Raid, Intercept, Final, Escort, Defend, Hunt, Mine, Field }

    public enum ElfTaskKind { Ambush, Mine, Labourers, Reclaim, Horse, Head }

    public static class Orders
    {
        /// Круг службы; Final выдаётся вместо очередного, когда служба дослужена.
        public static readonly OrderKind[] Rotation =
        {
            OrderKind.Hold, OrderKind.Slay, OrderKind.Raid, OrderKind.Intercept,
            OrderKind.Escort, OrderKind.Defend, OrderKind.Hunt, OrderKind.Mine, OrderKind.Field
        };

        /// Сдать столько приказов — и командование стражей твоё (GDD 9a).
        public const int OrdersForPromotion = 5;
        public const int OrdersForFinal = 5;

        public static readonly string[] Names =
        {
            "держать дворец", "проредить войско злодея", "набег на форт злодея",
            "перехватить караван", "последний бой", "сопроводить обоз",
            "оборонять дворец", "найти грабителей обоза", "отбить шахту", "разорить поле злодея",
        };

        static readonly string[] Briefs =
        {
            "Стой в точке дворца, пока он наш. Нужно {0} секунд.",
            "Убей {0} бойцов или самого злодея.",
            "Дойди до форта злодея и вернись живым во дворец.",
            "Разбей {0} караван злодея.",
            "Дойди до форта злодея и убей его сам. Это конец службы или конец тебя.",
            "Иди рядом с обозом стражи на обратном пути, пока он не доедет до склада.",
            "Убей {0} чужих у стен дворца.",
            "Найди и убей {0} из тех, кто грабил обоз стражи.",
            "Встань у любой шахты и продержись {0} секунд, пока рядом нет чужих.",
            "Снеси поле злодея: без еды его батраки голодают.",
        };

        public static readonly int[] Targets = { 25, 3, 2, 1, 1, 1, 3, 1, 20, 1 };

        static readonly int[][] Rewards =
        {
            new[] { 0, 0, 40, 0 }, new[] { 0, 0, 60, 10 }, new[] { 0, 0, 90, 20 },
            new[] { 0, 0, 120, 30 }, new[] { 0, 0, 300, 100 }, new[] { 0, 0, 70, 10 },
            new[] { 0, 0, 60, 10 }, new[] { 0, 0, 90, 20 }, new[] { 0, 0, 70, 20 },
            new[] { 0, 0, 80, 10 },
        };

        public const float EscortRadius = 40f;
        public const float EscortSeconds = 20f;
        public const float DefendRadius = 90f;
        public const float MineRadius = 45f;
        public const float RobberRadius = 30f;
        public static readonly V3 RaidPoint = new V3(-300f, 2f, 296f);
        public const float RaidRadius = 45f;
        public const float TalkRange = 8f;

        public static string NameOf(OrderKind kind) { return Names[(int)kind]; }
        public static int TargetOf(OrderKind kind) { return Targets[(int)kind]; }
        public static int[] RewardOf(OrderKind kind) { return Rewards[(int)kind]; }

        public static string BriefOf(OrderKind kind)
        {
            return string.Format(Briefs[(int)kind], Targets[(int)kind]);
        }

        public static string ProgressText(OrderKind kind, int progress)
        {
            int target = Targets[(int)kind];
            switch (kind)
            {
                case OrderKind.Final: return progress <= 0 ? "злодей ещё жив" : "выполнено";
                case OrderKind.Escort: return progress <= 0 ? "проводи обоз до склада" : "выполнено";
                case OrderKind.Field: return progress <= 0 ? "поле злодея стоит" : "выполнено";
                case OrderKind.Mine: return System.Math.Min(progress, target) + " из " + target + " с";
                case OrderKind.Raid:
                    if (progress <= 0) return "идти к форту злодея";
                    if (progress == 1) return "форт достигнут, вернуться во дворец";
                    return "выполнено";
                default: return System.Math.Min(progress, target) + " из " + target;
            }
        }

        /// Какой приказ дать следующим: после порога — последний бой; иначе
        /// очередной по кругу, пропуская невыполнимые сейчас (погоня без
        /// грабителей, поле, которого нет).
        public static OrderKind Next(int ordersDone, int rotationIndex, System.Func<OrderKind, bool> possible)
        {
            if (ordersDone >= OrdersForFinal) return OrderKind.Final;
            for (int step = 0; step < Rotation.Length; step++)
            {
                var kind = Rotation[(rotationIndex + step) % Rotation.Length];
                if (possible == null || possible(kind)) return kind;
            }
            return OrderKind.Hold;
        }
    }

    public static class ElfTasks
    {
        public static readonly ElfTaskKind[] Rotation =
        {
            ElfTaskKind.Ambush, ElfTaskKind.Mine, ElfTaskKind.Labourers, ElfTaskKind.Reclaim, ElfTaskKind.Horse
        };
        public const int HeadAfter = 5;

        public static readonly string[] Names =
        {
            "засада на обоз", "изгнать чужаков с шахты", "подрубить чужое хозяйство",
            "вернуть землю", "пригнать коня", "охота за головой",
        };

        static readonly string[] Briefs =
        {
            "Останови чужой обоз и возьми своё: уведи лошадей, разграбь или разбей повозку.",
            "Встань у любой шахты в нашем лесу и продержись {0} секунд, пока рядом нет чужих.",
            "Убей {0} батраков злодея или стражи: без рук их хозяйство встанет.",
            "Удержи любой хутор {0} секунд, пока рядом нет чужих: это древние земли.",
            "Приведи коня в поселение — верхом.",
            "Убей вожака злодея или командира стражи. Своими руками.",
        };

        public static readonly int[] Targets = { 1, 20, 3, 20, 1, 1 };

        /// Награда — золото: валюта эльфийской лавки.
        static readonly int[] RewardGold = { 50, 60, 70, 60, 50, 250 };

        public const float TalkRange = 8f;
        public const float HoldRadius = 35f;
        public const float VillageRadius = 60f;

        public static string NameOf(ElfTaskKind kind) { return Names[(int)kind]; }
        public static int TargetOf(ElfTaskKind kind) { return Targets[(int)kind]; }
        public static int[] RewardOf(ElfTaskKind kind) { return new[] { 0, 0, RewardGold[(int)kind], 0 }; }

        public static string BriefOf(ElfTaskKind kind)
        {
            return string.Format(Briefs[(int)kind], Targets[(int)kind]);
        }

        public static string ProgressText(ElfTaskKind kind, int progress)
        {
            int target = Targets[(int)kind];
            if (target == 1) return progress >= 1 ? "выполнено" : "ещё нет";
            return System.Math.Min(progress, target) + " из " + target;
        }

        public static ElfTaskKind Next(int tasksDone, int rotationIndex)
        {
            if (tasksDone >= HeadAfter) return ElfTaskKind.Head;
            return Rotation[rotationIndex % Rotation.Length];
        }
    }
}
