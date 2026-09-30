// Проверки ядра правил (unity_project/Assets/DjvaGoda/Core) без Unity.
//
// Собирается системным csc (C# 5) — см. core_tests/run.sh. Правила те же, что
// у наборов Godot-версии: набор объявляет, сколько проверок обязан выполнить,
// и меньше — провал; каждую новую проверку роняют поломкой.
using System;
using System.Collections.Generic;
using DjvaGoda.Core;

public static class CoreTests
{
    const int Expected = 45;
    static int _ran;
    static int _failed;

    static void Check(bool ok, string label, string detail)
    {
        _ran++;
        if (!ok) _failed++;
        Console.WriteLine("[ядро] " + (ok ? "OK    " : "ПРОВАЛ") + " | " + label + ": " + detail);
    }

    public static int Main()
    {
        Console.OutputEncoding = System.Text.Encoding.UTF8;
        Economy();
        Grades();
        Sides();
        Combat();
        Formations_();
        Mines();
        Treasury();
        Buildings();
        Match();
        OrdersAndTasks();
        Steward();
        Wounds();
        Character();

        if (_ran < Expected)
        {
            _failed++;
            Console.WriteLine("[ядро] ПРОВАЛ: выполнено " + _ran + " проверок из " + Expected);
        }
        Console.WriteLine(_failed == 0
            ? "[ядро] все проверки пройдены (" + _ran + ")"
            : "[ядро] провалено проверок: " + _failed + " из " + _ran);
        return _failed == 0 ? 0 : 1;
    }

    static void Economy()
    {
        var fitted = Res.Fit(new[] { 1, 2, 3, 4 });
        Check(fitted.Length == Res.Count && fitted[5] == 0 && fitted[3] == 4,
            "короткая цена подгоняется под все ресурсы", string.Join(",", Array.ConvertAll(fitted, x => x.ToString())));
        Check(Res.At(Res.BuildingCost(BuildingKind.Storage), ResourceKind.Food) == 0,
            "постройки не стоят еды — короткая цена читается нулём", "еда 0");
        Check(Res.FormatCost(Res.HorseCost) == "дер 25, зол 12",
            "цена пишется словами", Res.FormatCost(Res.HorseCost));
        Check(Res.At(Res.BuildingCost(BuildingKind.Stable), ResourceKind.Iron) == 0,
            "конюшня без железа — иначе злодей не получит железа никогда",
            Res.FormatCost(Res.BuildingCost(BuildingKind.Stable)));
    }

    static void Grades()
    {
        bool rising = true;
        for (int g = 1; g < Res.GradeHealth.Length; g++)
            rising &= Res.BuildingHealth(BuildingKind.Storage, g) > Res.BuildingHealth(BuildingKind.Storage, g - 1);
        Check(rising && Res.BuildingHealth(BuildingKind.Storage, 0) >= 1200f,
            "ступени крепче одна другой, дерево — вдвое крепче прежних 600",
            Res.BuildingHealth(BuildingKind.Storage, 0) + " … " + Res.BuildingHealth(BuildingKind.Storage, 3));
        Check(Res.At(Res.GradeCost(BuildingKind.Storage, 2), ResourceKind.Iron) > 0
            && Res.At(Res.GradeCost(BuildingKind.Storage, 1), ResourceKind.Iron) == 0,
            "железо — только на последнюю ступень", Res.FormatCost(Res.GradeCost(BuildingKind.Storage, 2)));
        Check(Res.GradeCost(BuildingKind.Storage, 3).Length == 0 && Res.GradeCost(BuildingKind.Farm, 0).Length == 0
            && Res.GradeCost(BuildingKind.ElfHouse, 0).Length == 0,
            "крепче камня с железом не бывает; у поля и домов эльфов ступеней нет", "пусто");
        Check(Res.Walkable(BuildingKind.Farm) && !Res.Walkable(BuildingKind.Storage),
            "поле проходимо, склад — нет", "поле");
    }

    static void Sides()
    {
        Check(Factions.Hostile(0, 2) && !Factions.Hostile(1, 1) && Factions.Hostile(-1, 1),
            "стороны враждуют, неизвестная — враг всем", "злодей/стража, эльфы/эльфы, -1");
        Factions.Overlord[(int)Faction.Guard] = (int)Faction.Villain;
        bool allied = !Factions.Hostile((int)Faction.Villain, (int)Faction.Guard);
        bool elvesStill = Factions.Hostile((int)Faction.Elves, (int)Faction.Guard);
        Factions.Overlord[(int)Faction.Guard] = -1;
        Check(allied && elvesStill, "взятый дворец: стража — союзник злодея, эльфам — враг", "поглощение");
        Check(Factions.MayBuild(Faction.Elves, BuildingKind.ElfHouse, false)
            && !Factions.MayBuild(Faction.Elves, BuildingKind.Storage, false)
            && !Factions.MayBuild(Faction.Guard, BuildingKind.Storage, false)
            && Factions.MayBuild(Faction.Guard, BuildingKind.Storage, true)
            && !Factions.MayBuild(Faction.Villain, BuildingKind.ElfHouse, false),
            "стройка: эльфам — дома, страже — только командиру, злодею — всё, кроме домов эльфов", "права");
        Check(Math.Abs(Factions.VillainHitScale(Faction.Villain, (int)Faction.Guard, 0, 0) - 0.1f) < 0.001f
            && Factions.VillainHitScale(Faction.Villain, (int)Faction.Guard, 2, 2) == 1f
            && Factions.VillainHitScale(Faction.Villain, (int)Faction.Elves, 0, 0) == 1f
            && Factions.VillainHitScale(Faction.Guard, (int)Faction.Villain, 0, 0) == 1f,
            "простая стража бьёт злодея в десятую силу, снаряжённая — в полную, прочие — как есть", "снаряжённость");
    }

    static void Combat()
    {
        Check(Weapons.Severs(WeaponKind.Sword) && !Weapons.Severs(WeaponKind.Bow) && Weapons.IsProjectile(WeaponKind.Spell),
            "меч отрубает, стрела калечит, шар — снаряд", "виды");
        Check(Weapons.GearName(2, true) == "булатное" && Weapons.GearName(2, false) == "эльфийское",
            "у кузни людей не «эльфийское», а «булатное»", Weapons.GearName(2, true));
    }

    static void Formations_()
    {
        float minX = float.MaxValue, maxX = float.MinValue;
        for (int i = 0; i < 8; i++)
        {
            var o = Formations.SlotOffset(FormationKind.Column, i);
            minX = Math.Min(minX, o.X);
            maxX = Math.Max(maxX, o.X);
        }
        float lineWidth = Formations.SlotOffset(FormationKind.Line, 7).X - Formations.SlotOffset(FormationKind.Line, 0).X;
        Check(maxX - minX < 3f && lineWidth > 12f, "колонна — по двое, шеренга — широкая",
            "колонна " + (maxX - minX) + " м, шеренга " + lineWidth + " м");
    }

    static void Treasury()
    {
        var wallet = new Wallet();
        wallet.Stored.Capacity = 400;
        wallet.Grant(new[] { 10, 0, 50, 0 });
        wallet.AddStored((int)ResourceKind.Gold, 100);
        wallet.Spend(new[] { 0, 0, 60, 0 });
        Check(wallet.Carried.GetAmount(ResourceKind.Gold) == 0 && wallet.Stored.GetAmount(ResourceKind.Gold) == 90,
            "платят сперва тем, что при себе, остаток — со склада",
            "при себе " + wallet.Carried.GetAmount(ResourceKind.Gold) + ", в складе " + wallet.Stored.GetAmount(ResourceKind.Gold));

        var full = new Wallet();
        full.Stored.Capacity = 100;
        full.Grant(new[] { 150, 0, 0, 0 });
        int moved = full.Deposit();
        Check(moved == 100 && full.Carried.GetAmount(ResourceKind.Wood) == 50,
            "склад не принимает сверх потолка — остаток остаётся при себе",
            "сдано " + moved + ", при себе " + full.Carried.GetAmount(ResourceKind.Wood));

        var lost = full.DropCarried();
        Check(lost[(int)ResourceKind.Wood] == 50 && full.GetAmount(ResourceKind.Wood) == 100,
            "смерть роняет только то, что при себе; склад — страховка",
            "выпало " + lost[(int)ResourceKind.Wood] + ", осталось " + full.GetAmount(ResourceKind.Wood));
    }

    static void Buildings()
    {
        var solo = new BuildingState(BuildingKind.Storage, Faction.Villain, false);
        var crew = new BuildingState(BuildingKind.Storage, Faction.Villain, false);
        for (int i = 0; i < 20; i++)
        {
            solo.Build(0.1f, 0);
            crew.Build(0.1f, 2);
        }
        Check(Math.Abs(crew.Progress - solo.Progress * 3f) < 0.01f && !solo.Done,
            "двое строителей — стройка втрое быстрее, без них всё равно идёт",
            "один " + solo.Progress + ", с двумя " + crew.Progress);

        var wall = new BuildingState(BuildingKind.Stable, Faction.Villain, true);
        wall.TakeDamage(500f, (int)Faction.Elves, 0, 0);
        wall.ApplyUpgrade();
        Check(wall.Grade == 1 && Math.Abs(wall.Health - (1200f - 500f + 800f)) < 0.1f,
            "укрепление прибавляет разницу ступеней — побитая стена остаётся побитой",
            "прочность " + wall.Health + " из " + wall.MaxHealth);

        var fort = new BuildingState(BuildingKind.Storage, Faction.Villain, true);
        float byGuard = fort.TakeDamage(100f, (int)Faction.Guard, 0, 0);
        float byElf = fort.TakeDamage(100f, (int)Faction.Elves, 0, 0);
        Check(Math.Abs(byGuard - 10f) < 0.01f && Math.Abs(byElf - 100f) < 0.01f,
            "простая стража ломает постройки злодея в десятую силу, эльфы — в полную",
            "стража " + byGuard + ", эльф " + byElf);

        var field = new BuildingState(BuildingKind.Farm, Faction.Villain, true);
        for (int i = 0; i < 100; i++) field.Grow(1f);
        var food = field.TakeGrown(12);
        Check(food[(int)ResourceKind.Food] == 12 && field.Grown[(int)ResourceKind.Food] == 13,
            "поле растит само, фермер уносит, сколько влезет в руки",
            "унёс " + food[(int)ResourceKind.Food] + ", осталось " + field.Grown[(int)ResourceKind.Food]);
    }

    static void Match()
    {
        var match = new MatchState();
        var villain = new List<Faction> { Faction.Villain };
        var said = new List<string>();
        for (int i = 0; i < 21; i++) said.AddRange(match.TickCapture(1f, villain));
        Check(match.PalaceOwner == Faction.Villain && match.GuardAbsorbed
            && !Factions.Hostile((int)Faction.Villain, (int)Faction.Guard),
            "злодей держит дворец 20 с — дворец его, стража — его союзник",
            string.Join(" / ", said.ToArray()));
        match.GuardAbsorbed = false;
        match.ApplyAlliances();

        var contested = new MatchState();
        for (int i = 0; i < 30; i++)
            contested.TickCapture(1f, new List<Faction> { Faction.Villain, Faction.Elves });
        Check(contested.PalaceOwner == Faction.Guard && contested.CaptureProgress == 0f,
            "оспоренный дворец не берётся", "прогресс " + contested.CaptureProgress);

        var elves = new MatchState();
        var alive = new SideSnapshot { HasPlayers = true, HasBarracks = true, ElfHouses = 0, LivingElves = 1 };
        var none = new SideSnapshot { HasPlayers = true, HasBarracks = true, ElfHouses = 0, LivingElves = 0 };
        bool stillIn = !elves.SideOut(Faction.Elves, alive);
        bool gone = elves.SideOut(Faction.Elves, none);
        Check(stillIn && gone, "эльфы выбывают, только когда нет ни домов, ни живых", "домов 0");

        var guard = new MatchState();
        guard.ReportLeaderDown(Faction.Guard, 0);
        var withBarracks = new SideSnapshot { HasPlayers = true, HasBarracks = true };
        var withoutBarracks = new SideSnapshot { HasPlayers = true, HasBarracks = false };
        Check(!guard.SideOut(Faction.Guard, withBarracks) && guard.SideOut(Faction.Guard, withoutBarracks),
            "стража сломлена, только когда пал командир И снесены казармы", "командир пал");

        var end = new MatchState();
        end.ReportLeaderDown(Faction.Villain, 1);
        var fresh = new SideSnapshot { HasPlayers = false, AiHeroExists = false };
        var sides = new[]
        {
            new SideSnapshot { HasPlayers = true },
            new SideSnapshot { HasPlayers = true, ElfHouses = 0, LivingElves = 0 },
            fresh,
        };
        var words = end.CheckVictories(sides);
        Check(end.Victors[(int)Faction.Guard] && end.SidesLeft() == 1 && !end.SideOut(Faction.Guard, fresh),
            "одна сторона осталась — ПОБЕДА; пустая сторона без вожака не выбывает сама",
            string.Join(" / ", words.ToArray()));
    }

    static void OrdersAndTasks()
    {
        var skipHunt = Orders.Next(2, 6, k => k != OrderKind.Hunt);
        Check(skipHunt == OrderKind.Mine && Orders.Next(5, 0, null) == OrderKind.Final,
            "невыполнимый приказ пропускается; после пяти сданных — последний бой",
            skipHunt + ", " + Orders.Next(5, 0, null));
        Check(Orders.BriefOf(OrderKind.Hold).Contains("25") && Orders.ProgressText(OrderKind.Raid, 1).Contains("вернуться"),
            "приказ пишется с числом, набег — ступенями", Orders.BriefOf(OrderKind.Hold));
        Check(ElfTasks.Next(5, 2) == ElfTaskKind.Head && ElfTasks.Next(2, 2) == ElfTaskKind.Labourers
            && ElfTasks.RewardOf(ElfTaskKind.Head)[(int)ResourceKind.Gold] == 250,
            "старейшина: по кругу, после пяти — охота за головой, награда — золотом", "задания");
    }

    static void Steward()
    {
        var has = new HashSet<BuildingKind> { BuildingKind.Storage, BuildingKind.Stable, BuildingKind.Farm };
        var hungry = new EconomyView { Crew = 9, FieldsAll = 1, Has = has };
        var fed = new EconomyView { Crew = 4, FieldsAll = 1, Has = has };
        Check(StewardRules.NextBuilding(hungry) == BuildingKind.Farm && StewardRules.NextBuilding(fed) == BuildingKind.House,
            "девять ртов на одном поле — ещё поле; сытые — дальше по очереди",
            StewardRules.NextBuilding(hungry) + " / " + StewardRules.NextBuilding(fed));

        var atMine = StewardRules.AssignRoles(new EconomyView { Crew = 6, CaravanAtMine = true, OreNearby = false }, null, null);
        var noOre = StewardRules.AssignRoles(new EconomyView { Crew = 4, OreNearby = false }, new[] { 0, 99 }, new Wallet());
        Check(atMine[(int)LabourerRole.Miner] == 2 && atMine[(int)LabourerRole.Lumberjack] == 4
            && noOre[(int)LabourerRole.Miner] == 0 && noOre[(int)LabourerRole.Lumberjack] == 4,
            "обоз у шахты — двое копают; копать рядом нечего — все на лес, даже когда нужен камень",
            "шахтёров " + atMine[(int)LabourerRole.Miner] + " и " + noOre[(int)LabourerRole.Miner]);

        var rich = new Wallet();
        rich.Grant(new[] { 100, 100, 100, 100, 0, 0 });
        Check(StewardRules.PickOre(rich, true) == ResourceKind.Coal && StewardRules.PickOre(rich, false) != ResourceKind.Coal,
            "с кузней — за углём, когда его меньше всего; без кузни уголь не возят",
            StewardRules.PickOre(rich, true) + " / " + StewardRules.PickOre(rich, false));

        Check(StewardRules.CaravanGuards(2) == 0 && StewardRules.CaravanGuards(3) == 1 && StewardRules.CaravanGuards(8) == 2,
            "в охрану обоза — только сверх двух работающих", "охрана при 2, 3, 8 батраках");
        Check(!StewardRules.ShouldHire(new EconomyView { Crew = 2, Horses = 0 })
            && StewardRules.ShouldHire(new EconomyView { Crew = 2, Horses = 1 }),
            "без лошади — не больше двух батраков: золото нужно на лошадь", "наём");
    }

    static void Wounds()
    {
        var cut = new BodyState();
        cut.RegisterHit("arm_r", 50f, WeaponKind.Sword);
        var shot = new BodyState();
        shot.RegisterHit("arm_r", 50f, WeaponKind.Bow);
        Check(cut.IsSevered(Limb.ArmR) && cut.Bleeding && shot.IsCrippled(Limb.ArmR) && !shot.IsSevered(Limb.ArmR) && !shot.Bleeding,
            "меч отрубает руку и открывает кровь, стрела калечит без крови",
            cut.Summary() + " / " + shot.Summary());

        shot.RegisterHit("arm_r", 1f, WeaponKind.Axe);
        Check(shot.IsSevered(Limb.ArmR), "покалеченная рука — на один рубящий удар от потери", shot.Summary());

        var legs = new BodyState();
        legs.RegisterHit("leg_l", 50f, WeaponKind.Sword);
        float crawl = legs.MoveSpeed(6f);
        legs.GrantProsthetic(Limb.LegL, 3);
        float master = legs.MoveSpeed(6f);
        Check(Math.Abs(crawl - BodyState.CrawlSpeedOne) < 0.001f && master > 6f && !legs.IsCrawling(),
            "без ноги ползёшь, мастерский протез — быстрее живой",
            "ползком " + crawl + ", с протезом " + master);

        var bleeding = new BodyState();
        bleeding.RegisterHit("arm_l", 50f, WeaponKind.Axe);
        float lost = bleeding.Tick(10f);
        bool bandaged = bleeding.ApplyBandage();
        Check(Math.Abs(lost - 30f) < 0.01f && bandaged && !bleeding.Bleeding && bleeding.Bandages == 2,
            "кровотечение: три в секунду, бинт останавливает", "за 10 с " + lost);

        var head = new BodyState();
        head.RegisterHit("head", 85f, WeaponKind.Hammer);
        Check(head.EyesLost == 2 && Math.Abs(head.Blindness() - 1f) < 0.001f && head.GrantEye() && head.Blindness() < 1f,
            "удары по голове выбивают глаза; некротический глаз возвращает зрение",
            "потеряно " + head.EyesLost);
    }

    static void Character()
    {
        var runner = new Vitals();
        int ran = 0;
        while (ran < 200 && runner.TickRun(0.1f, true, false)) ran++;
        bool winded = runner.Winded;
        bool blocked = !runner.TickRun(0.1f, true, false);
        Check(ran >= 99 && ran <= 101 && winded && blocked && runner.Stamina < Vitals.StaminaFloor,
            "десять секунд бега — и выдохся; бежать снова нельзя, пока не отдышишься",
            "бежал " + ran + " тактов, выносливость " + runner.Stamina);

        for (int i = 0; i < 20; i++) runner.TickRun(0.1f, false, false);
        Check(!runner.Winded && runner.TickRun(0.1f, true, false),
            "набрал второе дыхание — снова бежит", "выносливость " + runner.Stamina);

        var hero = new Vitals();
        hero.Experience = 120;
        bool first = hero.BuyLevel(Stat.Health);
        bool second = hero.BuyLevel(Stat.Health);
        bool third = hero.BuyLevel(Stat.Health);
        Check(first && second && !third && hero.MaxHealth == 130f && hero.Experience == 0,
            "прокачка за опыт: цена растёт, прибавка поверх базы",
            "здоровье " + hero.MaxHealth + ", опыта осталось " + hero.Experience);
    }

    static void Mines()
    {
        var idle = new MineState(ResourceKind.Iron);
        var worked = new MineState(ResourceKind.Iron);
        for (int t = 0; t < 100; t++)
        {
            worked.Dig(1);
            worked.Dig(2);
            idle.Tick(0.1f);
            worked.Tick(0.1f);
        }
        int a = idle.Stored[(int)ResourceKind.Iron];
        int b = worked.Stored[(int)ResourceKind.Iron];
        Check(b > a * 3 && a > 0, "двое копателей — шахта копит в разы быстрее; без них — едва",
            "без рабочих " + a + ", с двумя " + b + " за 10 с");
        var full = new MineState(ResourceKind.Stone);
        for (int t = 0; t < 2000; t++) full.Tick(1f);
        var took = full.Take(120);
        Check(full.Stored[(int)ResourceKind.Stone] == MineState.StockpileCap - 120 && took[(int)ResourceKind.Stone] == 120,
            "шахта копит до потолка, обоз забирает сколько влезет",
            "осталось " + full.Stored[(int)ResourceKind.Stone]);
    }
}
