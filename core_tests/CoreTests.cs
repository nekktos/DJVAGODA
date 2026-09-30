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
    const int Expected = 138;
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
        Caravans();
        Map();
        HungerRules();
        Keys();
        DealsRules();
        ServiceRules();
        ElderRules();
        Damage();
        Spells();
        Loot();
        Saves();
        ReliefRules();
        WarbandRules();
        HeroRules();
        RespawnRules();
        CommanderRules();
        PlacementRules();
        TripRules();
        LabourerRules();
        UnitRules();
        ForestRules();

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

    static void Caravans()
    {
        Check(CaravanRules.SpeedFor(0) == 0f && CaravanRules.SpeedFor(3) > CaravanRules.SpeedFor(1),
            "без лошади обоз не едет, больше лошадей — быстрее",
            CaravanRules.SpeedFor(1) + " → " + CaravanRules.SpeedFor(3));
        Check(CaravanRules.ActionFor(Faction.Villain, Faction.Guard, 2, true, 50, true) == CaravanAction.Intercept
            && CaravanRules.ActionFor(Faction.Villain, Faction.Guard, 2, true, 50, false) == CaravanAction.Rob
            && CaravanRules.ActionFor(Faction.Elves, Faction.Guard, 2, true, 50, false) == CaravanAction.Rob
            && CaravanRules.ActionFor(Faction.Elves, Faction.Guard, 0, true, 50, false) == CaravanAction.Plunder
            && CaravanRules.ActionFor(Faction.Elves, Faction.Guard, 2, false, 50, false) == CaravanAction.None,
            "перехват — сопернику со складом; эльфы уводят лошадей и грабят; на ходу — ничего", "действия");
        var wallet = new Wallet();
        wallet.Stored.Capacity = 100;
        var cargo = new[] { 0, 0, 0, 120, 0, 0 };
        bool all = CaravanRules.Unload(cargo, wallet);
        Check(!all && cargo[(int)ResourceKind.Iron] == 20 && wallet.Stored.GetAmount(ResourceKind.Iron) == 100,
            "полный склад: выгружено, сколько влезло, остаток ждёт в обозе",
            "в обозе осталось " + cargo[(int)ResourceKind.Iron]);
    }

    static void Map()
    {
        var iron = MapLayout.MineOf(ResourceKind.Iron).Value.At;
        float toVillain = iron.FlatDistance(Factions.Spawn[(int)Faction.Villain]);
        float toGuard = iron.FlatDistance(Factions.Spawn[(int)Faction.Guard]);
        Check(Math.Abs(toVillain - toGuard) < 5f,
            "железная шахта — поровну злодею и страже", toVillain + " против " + toGuard);
        var elves = MapLayout.ZoneCenters[(int)Zone.Elves];
        bool outward = true;
        foreach (var mine in MapLayout.Mines)
            outward &= MapLayout.MineEntrance(mine.At).FlatDistance(elves) > mine.At.FlatDistance(elves);
        Check(outward, "входы шахт смотрят прочь от поселения эльфов", "все четыре");
    }

    static void HungerRules()
    {
        var rich = new Wallet();
        rich.Grant(new[] { 0, 0, 0, 0, 100, 0 });
        var fedHunger = new[] { 2, 1, 0 };
        var fed = Hunger.Feed(Faction.Villain, rich, fedHunger);
        Check(fed.Fed && fedHunger[0] == 0 && rich.GetAmount(ResourceKind.Food) == 100 - 3 * Res.FeedPerWorker,
            "сытая артель съедает свою долю, голод прощён", "осталось еды " + rich.GetAmount(ResourceKind.Food));

        var poor = new Wallet();
        poor.Grant(new[] { 0, 0, 0, 0, 20, 0 });
        var crew = new[] { 0, 0, 0 };
        var first = Hunger.Feed(Faction.Villain, poor, crew);
        var second = Hunger.Feed(Faction.Villain, poor, crew);
        var third = Hunger.Feed(Faction.Villain, poor, crew);
        Check(!first.Fed && first.Starved == 0 && second.Starved == 0 && third.Starved == 3
            && poor.GetAmount(ResourceKind.Food) == 20,
            "не хватило на всех — не ест никто; умирают только с третьего пропуска",
            third.Message);
    }

    static void Keys()
    {
        var map = KeyActions.Defaults();
        var clashes = new List<string>();
        foreach (var action in KeyActions.All)
            foreach (var key in action.Defaults)
                foreach (var other in KeyActions.Conflicts(action.Name, key, map))
                    clashes.Add(action.Name + "=" + other);
        Check(clashes.Count == 0, "в раскладке по умолчанию нет конфликтов — B в бою и сверху не мешают",
            clashes.Count == 0 ? "чисто" : string.Join(", ", clashes.ToArray()));

        KeyActions.Rebind(map, "jump", "<Keyboard>/w");
        Check(map["jump"][0] == "<Keyboard>/w" && map["move_forward"][0] == "<Keyboard>/space"
            && KeyActions.Conflicts("jump", "<Keyboard>/w", map).Count == 0,
            "переназначение на занятую клавишу меняет их местами", "прыжок на W, вперёд на пробел");
    }

    static void DealsRules()
    {
        var villain = new Kit { Side = Faction.Villain };
        var wallet = new Wallet();
        wallet.Grant(new[] { 0, 0, 500, 500, 0, 0 });
        var noPotion = Deals.Trade(villain, new BodyState(), wallet, TradeItem.PotionHeal, true);
        var armor = Deals.Trade(villain, new BodyState(), wallet, TradeItem.Armor, true);
        Check(!noPotion.Ok && noPotion.Refusal == "этого в вашей лавке не продают" && armor.Ok && villain.ArmorTier == 1,
            "лавка продаёт только свой товар: злодею — латы, зелий нет", noPotion.Refusal);

        var noCoal = Deals.ForgeGear(villain, wallet, true);
        wallet.Carried.Capacity = 600;
        wallet.Add((int)ResourceKind.Coal, 50);
        var forged = Deals.ForgeGear(villain, wallet, true);
        Check(!noCoal.Ok && noCoal.Refusal.Contains("уголь") && forged.Ok && villain.GearTier == 1
            && villain.GearTitle(2) == "булатное",
            "без угля кузня не закаляет и говорит, где его взять; с углём — закаляет", noCoal.Refusal);

        var elf = new Kit { Side = Faction.Elves };
        var far = Deals.Build(elf, wallet, BuildingKind.ElfHouse, true, 60f, 0, 5);
        var full = Deals.Build(elf, wallet, BuildingKind.ElfHouse, true, 10f, 5, 5);
        var storage = Deals.Build(elf, wallet, BuildingKind.Storage, true, 10f, 0, 5);
        Check(!far.Ok && !full.Ok && !storage.Ok && full.Refusal.Contains("5 из 5"),
            "эльф строит дом рядом с собой, не сверх предела и не склад", full.Refusal);

        Check(Deals.SquadCapacity(0) == 3 && Deals.SquadCapacity(2) == 9 && Deals.SquadCapacity(10) == 12,
            "войско: трое без домов, каждый дом — ещё трое, потолок двенадцать", "вместимость");

        var poor = new Wallet();
        var send = Deals.SendCaravan(poor, true, 0, new[] { new V3(0f, 0f, 0f) });
        var outside = Deals.SendCaravan(poor, true, 0, new[] { new V3(700f, 0f, 0f) });
        Check(!send.Ok && send.Refusal.Contains("лошад") && !outside.Ok,
            "обоз без свободных лошадей не выезжает; точка вне карты — отказ", send.Refusal);
    }

    static void ServiceRules()
    {
        var guard = new ServiceRecord();
        var pay = new Wallet();
        pay.Carried.Capacity = 2000;
        guard.Report(pay, true, null);
        guard.TickHold(30f, true, false);
        int whileLost = guard.Progress;
        guard.TickHold(26f, true, true);
        string done = guard.Report(pay, true, null);
        Check(whileLost == 0 && guard.OrdersDone == 1 && pay.GetAmount(ResourceKind.Gold) == 40 && done.Contains("выполнен"),
            "держать дворец — только пока он наш; сдан — оплачен, выдан следующий", done);

        var hero = new ServiceRecord();
        string early = hero.Promote(true, true, false);
        hero.OrdersDone = 5;
        Check(early.Contains("0 из 5") && hero.CanPromote(true, true, false) && !hero.CanPromote(true, true, true),
            "командование — после пяти сданных и только если командира нет", early);

        var final = new ServiceRecord { OrdersDone = 5 };
        final.Report(pay, true, null);
        bool isFinal = final.Order == OrderKind.Final;
        final.OnKill(Faction.Villain, false, false, false);
        bool pawnDoesNotCount = !final.Done;
        string failed = final.OnDeath();
        Check(isFinal && pawnDoesNotCount && failed != null && final.FinalThreshold == 10 && !final.Order.HasValue,
            "последний бой — за личное убийство злодея; погиб — провален, заслужи снова",
            "порог " + final.FinalThreshold);
    }

    static void ElderRules()
    {
        var elf = new ElfTaskRecord { TasksDone = 2 };
        var pay = new Wallet();
        pay.Carried.Capacity = 2000;
        string issued = elf.Report(pay, false, true);
        Check(elf.Task == ElfTaskKind.Reclaim && issued.Contains("вернуть землю"),
            "«подрубить хозяйство» не дают, пока у врагов нет батраков", issued);

        elf.TickHold(15f, true, 1);
        int contested = elf.Progress;
        elf.TickHold(21f, true, 0);
        string paid = elf.Report(pay, true, true);
        Check(contested == 0 && pay.GetAmount(ResourceKind.Gold) == 60 && elf.TasksDone == 3,
            "хутор держат, пока рядом нет чужих; сдано — золото", paid);
    }

    static void Damage()
    {
        float plain = DamageRules.Outgoing(WeaponKind.Sword, "head", 0, false);
        float tempered = DamageRules.Outgoing(WeaponKind.Sword, "head", 2, false);
        float withered = DamageRules.Outgoing(WeaponKind.Sword, "torso", 0, true);
        Check(plain == 70f && Math.Abs(tempered - 108.5f) < 0.01f && Math.Abs(withered - 35f * 0.65f) < 0.01f,
            "удар: голова вдвое, закалка сильнее, увядший бьёт слабее",
            plain + " / " + tempered + " / " + withered);

        float wallSword = DamageRules.ToUnit(100f, FormationKind.ShieldWall, false, WeaponKind.Sword);
        float wallBolt = DamageRules.ToUnit(100f, FormationKind.ShieldWall, false, WeaponKind.Crossbow);
        Check(Math.Abs(wallSword - 60f) < 0.01f && wallBolt > wallSword && wallBolt < 100f,
            "стена щитов держит меч, арбалет её пробивает, но не целиком", wallSword + " / " + wallBolt);

        var villain = new Kit { Side = Faction.Villain, ArmorTier = 2 };
        float byGuard = DamageRules.ToCharacter(100f, villain, (int)Faction.Guard, 0, 0);
        float byElf = DamageRules.ToCharacter(100f, villain, (int)Faction.Elves, 0, 0);
        Check(Math.Abs(byGuard - 6.6f) < 0.01f && Math.Abs(byElf - 66f) < 0.01f,
            "на злодее в латах: доспех режет всё, простая стража — ещё вдесятеро", byGuard + " / " + byElf);

        Check(DamageRules.Blast(0f, "torso", 0) == 45f && DamageRules.Blast(6f, "torso", 0) == 0f,
            "взрыв шара: в центре полный, к краю радиуса — на нет", "центр 45, край 0");
    }

    static void Spells()
    {
        var caster = new SpellState();
        var vitals = new Vitals();
        string why;
        var start = caster.Begin(Faction.Villain, AbilityKind.Paralysis, vitals, new BodyState(), out why);
        caster.Tick(1f);
        caster.OnDamaged();
        AbilityKind? finished = null;
        for (int i = 0; i < 20; i++) finished = finished ?? caster.Tick(0.1f);
        Check(start == CastStart.Casting && !finished.HasValue && caster.Ready(AbilityKind.Paralysis)
            && vitals.Mana == Vitals.BaseMana,
            "паралич кастуется долго; удар срывает каст — ни отката, ни маны", "сорван");

        var clean = new SpellState();
        clean.Begin(Faction.Villain, AbilityKind.Paralysis, vitals, null, out why);
        AbilityKind? done = null;
        for (int i = 0; i < 20 && !done.HasValue; i++) done = clean.Tick(0.1f);
        Check(done == AbilityKind.Paralysis, "несорванный каст завершается сам", "каст закончен");

        var victim = new SpellState();
        victim.ApplyParalysis(Abilities.ParalysisHold);
        for (int i = 0; i < 40; i++) victim.Tick(0.1f);
        bool immune = !victim.ApplyParalysis(3f);
        for (int i = 0; i < 260; i++) victim.Tick(0.1f);
        bool again = victim.ApplyParalysis(3f);
        Check(immune && again, "после паралича — окно неуязвимости 25 с, потом снова можно", "окно");

        var elf = new SpellState();
        var nope = elf.Begin(Faction.Elves, AbilityKind.Paralysis, vitals, null, out why);
        var poor = new Vitals { Mana = 10f };
        var broke = elf.Begin(Faction.Elves, AbilityKind.Summon, poor, null, out why);
        Check(nope == CastStart.Refused && broke == CastStart.Refused && why.Contains("маны"),
            "чужое заклинание не колдуется; без маны — отказ с числами", why);
    }

    static void Loot()
    {
        var fallen = new Kit { Side = Faction.Guard, GearTier = 2, ArmorTier = 1, PotionsHeal = 0, Arrows = 40 };
        var fallenBody = new BodyState { Bandages = 5 };
        var pile = LootPile.FromBody(new[] { 0, 0, 30, 10 }, fallen, fallenBody);

        var looter = new Kit { Side = Faction.Elves, GearTier = 0, ArmorTier = 2, Arrows = 50 };
        var looterBody = new BodyState { Bandages = 8 };
        var wallet = new Wallet();
        int took = pile.Collect(wallet, looter, looterBody);
        Check(took > 0 && pile.Taken && looter.GearTier == 2 && looter.ArmorTier == 2
            && looterBody.Bandages == Res.BandageLimit && looter.Arrows == Res.QuiverLimit
            && wallet.GetAmount(ResourceKind.Gold) == 30,
            "смерть роняет всё; подобравший берёт лучшее снаряжение и расходники до потолков",
            pile.Summary());
        Check(pile.Collect(wallet, looter, looterBody) == 0, "подобранную кучу второй раз не взять", "пусто");
    }

    static void Saves()
    {
        var match = new MatchState { PalaceOwner = Faction.Villain, GuardAbsorbed = true };
        match.Out[(int)Faction.Guard] = true;
        var save = new SaveData();
        save.CaptureMatch(match);
        var restored = new MatchState();
        save.RestoreMatch(restored);
        bool allied = !Factions.Hostile((int)Faction.Villain, (int)Faction.Guard);
        restored.GuardAbsorbed = false;
        restored.ApplyAlliances();
        Check(restored.PalaceOwner == Faction.Villain && restored.Out[(int)Faction.Guard] && allied,
            "исход партии переживает выход — и союз стражи со злодеем тоже", "дворец у злодея");

        var wallet = new Wallet { Horses = 7, HorsesOut = 3 };
        wallet.Stored.Capacity = 400;
        wallet.AddStored((int)ResourceKind.Iron, 120);
        var saved = SaveData.CaptureTreasury(Faction.Villain, wallet);
        var back = new Wallet();
        SaveData.RestoreTreasury(saved, back);
        Check(back.Horses == 7 && back.HorsesOut == 0 && back.Stored.GetAmount(ResourceKind.Iron) == 120 && back.Stored.Capacity == 400,
            "казна и конюшня переживают выход; лошади в пути возвращаются", "лошадей " + back.Horses);
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

    static void ReliefRules()
    {
        var relief = Relief.ForMap();
        var mustBeFlat = new List<V3>(MapLayout.ZoneCenters);
        mustBeFlat.AddRange(MapLayout.Traders);
        mustBeFlat.Add(MapLayout.Workbench);
        mustBeFlat.Add(MapLayout.RampFoot);
        mustBeFlat.Add(new V3(0f, 0f, 0f));
        mustBeFlat.Add(new V3(0f, 0f, -410f));
        mustBeFlat.Add(new V3(530f, 0f, 0f));
        mustBeFlat.Add(new V3(600f, 0f, 150f));
        var emperor = MapLayout.ZoneCenters[(int)Zone.Emperor];
        mustBeFlat.Add(new V3(emperor.X + 180f, 0f, emperor.Z + 180f));
        foreach (var mine in MapLayout.Mines)
        {
            mustBeFlat.Add(mine.At);
            mustBeFlat.Add(MapLayout.MineEntrance(mine.At));
        }
        string bump = "";
        foreach (var at in mustBeFlat)
            if (relief.Height(at.X, at.Z) != 0f) bump += at + "=" + relief.Height(at.X, at.Z) + " ";
        Check(bump == "", "рельеф плоский под зонами, лавками, дорогами, плато, шахтами и у края",
            bump == "" ? mustBeFlat.Count + " точек на нуле" : bump);

        float top = 0f, lowest = 0f, steepest = 0f;
        int hilly = 0, cells = 0;
        float half = MapLayout.WorldSize * 0.5f;
        for (float x = -half; x <= half; x += Relief.Cell)
            for (float z = -half; z <= half; z += Relief.Cell)
            {
                float h = relief.Height(x, z);
                cells++;
                if (h > 2f) hilly++;
                top = Math.Max(top, h);
                lowest = Math.Min(lowest, h);
                float dx = relief.Height(x + Relief.Cell, z) - h;
                float dz = relief.Height(x, z + Relief.Cell) - h;
                float slope = (float)(Math.Atan(Math.Sqrt(dx * dx + dz * dz) / Relief.Cell) * 180.0 / Math.PI);
                steepest = Math.Max(steepest, slope);
            }
        Check(top > 8f && hilly * 10 > cells, "холмы на карте есть, а не бильярдный стол",
            "вершина " + top.ToString("0.0") + " м, холмистых клеток " + hilly + " из " + cells);
        Check(lowest >= 0f && steepest < 30f, "земля только растёт вверх, и уклон с запасом ниже потолка навигации 45°",
            "низ " + lowest + ", круче всего " + steepest.ToString("0.0") + "°");
        var again = Relief.ForMap();
        Check(again.Height(-120f, 215f) == relief.Height(-120f, 215f) && again.Height(410f, 77f) == relief.Height(410f, 77f),
            "рельеф одинаков у хоста и клиента: то же зерно — те же холмы", "высота " + relief.Height(-120f, 215f).ToString("0.00"));
    }

    static List<V3> BandAt(V3 at, int count)
    {
        var band = new List<V3>();
        for (int i = 0; i < count; i++) band.Add(new V3(at.X + i, at.Y, at.Z));
        return band;
    }

    static void WarbandRules()
    {
        var elfHome = Factions.Spawn[(int)Faction.Elves];
        var villainFort = new V3(-300f, 0f, 290f);
        var elves = new WarbandBrain(Faction.Elves);
        var view = new WarbandView { Band = BandAt(elfHome, AiStats.GarrisonSize) };
        view.Buildings.Add(new SidedPoint(villainFort, (int)Faction.Villain));
        elves.Think(view, null);
        Check(elves.State == WarbandState.March && elves.Goal.HasValue && elves.Goal.Value.Distance(villainFort) < 0.1f
            && elves.Announced.HasValue,
            "полный отряд эльфов идёт в набег на постройку злодея в 600 м и объявляет его", elves.StateName);

        var guard = new WarbandBrain(Faction.Guard);
        var guardView = new WarbandView { Band = BandAt(Factions.Spawn[(int)Faction.Guard], AiStats.GarrisonSize) };
        guardView.Buildings.Add(new SidedPoint(villainFort, (int)Faction.Villain));
        guardView.Buildings.Add(new SidedPoint(elfHome, (int)Faction.Elves));
        guard.Think(guardView, null);
        bool guardHome = guard.State == WarbandState.Hold;
        guardView.SidesLeft = 2;
        guard.Think(guardView, null);
        Check(guardHome && guard.State == WarbandState.March && guard.Goal.Value.Distance(elfHome) < 0.1f,
            "стража не достаёт до форта (805 м > 800) и не трогает эльфов, пока в партии три стороны",
            "при двух сторонах цель " + guard.Goal);

        var villain = new WarbandBrain(Faction.Villain);
        var villainView = new WarbandView { Band = BandAt(Factions.Spawn[(int)Faction.Villain], AiStats.GarrisonSize) };
        villainView.Buildings.Add(new SidedPoint(new V3(-300f, 0f, -250f), (int)Faction.Elves));
        villainView.SidesLeft = 2;
        villain.Think(villainView, null);
        bool settling = villain.State == WarbandState.Hold;
        villainView.HasBarracks = true;
        villain.Think(villainView, null);
        Check(settling && villain.State == WarbandState.March,
            "гарнизон злодея под ИИ сидит дома, пока нет казармы: он — вся его оборона", villain.StateName);

        var order = elves.Steer(view.Band).Value;
        Check(Math.Abs(order.Anchor.FlatDistance(WarbandBrain.BandPoint(view.Band).Value) - AiStats.LeadDistance) < 0.1f
            && order.Formation == FormationKind.Column && order.Leash == AiStats.MarchLeash,
            "в походе якорь строя — в 14 м впереди вдоль маршрута, колонной, на коротком поводке",
            "якорь " + order.Anchor);

        view.Fighters.Add(new SidedPoint(order.Anchor + new V3(10f, 0f, 0f), (int)Faction.Villain));
        elves.Think(view, null);
        Check(elves.State == WarbandState.Fight && elves.Steer(view.Band).Value.Formation == FormationKind.Line,
            "враг у якоря — отряд принимает бой и встаёт линией", elves.StateName);

        var thinned = new WarbandBrain(Faction.Elves);
        var march = new WarbandView { Band = BandAt(elfHome, AiStats.GarrisonSize) };
        march.Buildings.Add(new SidedPoint(villainFort, (int)Faction.Villain));
        thinned.Think(march, null);
        march.Band = BandAt(elfHome + new V3(0f, 0f, 200f), 1);
        thinned.Think(march, null);
        Check(thinned.State == WarbandState.Return && thinned.Goal.Value.Distance(elfHome) < 0.1f,
            "отряд проредили на марше до одного — бросает набег и уходит домой", thinned.StateName);

        var keeper = new WarbandBrain(Faction.Elves);
        var home = new WarbandView { Band = BandAt(elfHome, AiStats.GarrisonSize) };
        var house = elfHome + new V3(60f, 0f, 60f);
        home.Posts.Add(house);
        home.Fighters.Add(new SidedPoint(house + new V3(12f, 0f, 0f), (int)Faction.Guard));
        keeper.Think(home, null);
        Check(keeper.State == WarbandState.March && keeper.Defending && keeper.StateName == "защищает хозяйство",
            "враг у своего дома — отряд идёт защищать хозяйство", keeper.StateName);

        var cart = new CartSighting { Id = 7, At = new V3(0f, 0f, 0f), Side = (int)Faction.Villain };
        for (int i = 1; i <= 10; i++) cart.Ahead.Add(new V3(0f, 0f, 30f * i));
        var hunter = new WarbandBrain(Faction.Elves);
        var meet = hunter.Intercept(BandAt(new V3(60f, 0f, 150f), 4), cart);
        float cartTime = meet.Z / CaravanRules.Speed;
        float bandTime = new V3(60f, 0f, 150f).FlatDistance(meet) / UnitStats.BaseSpeed;
        Check(meet.Z > 0f && bandTime <= cartTime && meet.Z < 300f,
            "перехват: первая точка пути обоза, куда отряд успеет раньше него", "встреча на " + meet);

        var slow = new WarbandBrain(Faction.Elves);
        var stuckView = new WarbandView { Band = BandAt(elfHome, AiStats.GarrisonSize) };
        stuckView.Buildings.Add(new SidedPoint(villainFort, (int)Faction.Villain));
        slow.Think(stuckView, null);
        int thoughts = 0;
        while (slow.State == WarbandState.March && thoughts < 30)
        {
            slow.Think(stuckView, null);
            thoughts++;
        }
        Check(slow.State == WarbandState.Return && thoughts * AiStats.WarbandThink >= AiStats.StuckSeconds,
            "отряд, не сдвинувшийся за 24 с похода, бросает набег и идёт домой",
            "сдался через " + thoughts * AiStats.WarbandThink + " с");
    }

    static HeroView VillainHero(V3 at)
    {
        var view = new HeroView { Side = Faction.Villain, At = at, Weapon = WeaponKind.Sword };
        return view;
    }

    static void HeroRules()
    {
        var at = new V3(0f, 0f, 0f);
        var far = VillainHero(at);
        far.Others.Add(new SidedPoint(new V3(20f, 0f, 0f), (int)Faction.Guard));
        var shot = HeroBrain.Decide(far);
        var near = VillainHero(at);
        near.Others.Add(new SidedPoint(new V3(3f, 0f, 0f), (int)Faction.Guard));
        var swing = HeroBrain.Decide(near);
        Check(shot.Task == HeroTask.Fight && shot.Weapon == WeaponKind.Spell && shot.Attack && shot.NeedsClearThrow
            && swing.Weapon == WeaponKind.Hammer && swing.Attack && !swing.NeedsClearThrow,
            "герой злодея издали бросает огненный шар (с проверкой броска), вплотную бьёт молотом",
            "20 м — " + shot.Weapon + ", 3 м — " + swing.Weapon);

        var middle = VillainHero(at);
        middle.Others.Add(new SidedPoint(new V3(7f, 0f, 0f), (int)Faction.Guard));
        var step = HeroBrain.Decide(middle);
        var archer = new HeroView { Side = Faction.Elves, At = at, Weapon = WeaponKind.Bow };
        archer.Others.Add(new SidedPoint(new V3(6f, 0f, 0f), (int)Faction.Villain));
        var loose = HeroBrain.Decide(archer);
        Check(step.Weapon == WeaponKind.Hammer && !step.Attack && step.Walk && loose.Attack && loose.Weapon == WeaponKind.Bow,
            "в 7 м шар взорвался бы на самом герое: он берёт молот и подходит; лук в упор стреляет",
            "атака молотом " + step.Attack + ", луком " + loose.Attack);

        var escort = VillainHero(at);
        escort.OwnCart = new V3(-10f, 0f, 0f);
        escort.Others.Add(new SidedPoint(new V3(25f, 0f, 0f), (int)Faction.Guard));
        var stay = HeroBrain.Decide(escort);
        escort.Others.Clear();
        escort.Others.Add(new SidedPoint(new V3(10f, 0f, 0f), (int)Faction.Guard));
        var fight = HeroBrain.Decide(escort);
        Check(stay.Goal.FlatDistance(escort.OwnCart.Value) < 0.1f && fight.Goal.FlatDistance(new V3(10f, 0f, 0f)) < 0.1f,
            "поводок: за врагом, уводящим от обоза, не гонится, а напавшего рядом бьёт",
            "цель издали " + stay.Goal + ", вблизи " + fight.Goal);

        var keeper = VillainHero(at);
        keeper.WarbandAnchor = new V3(-50f, 0f, 0f);
        keeper.Posts.Add(new V3(100f, 0f, 0f));
        keeper.Others.Add(new SidedPoint(new V3(110f, 0f, 0f), (int)Faction.Elves));
        var defend = HeroBrain.Decide(keeper);
        Check(defend.Task == HeroTask.Defend && defend.Goal.FlatDistance(new V3(110f, 0f, 0f)) < 0.1f && defend.Walk,
            "враг у своей постройки в 100 м — герой идёт защищать", defend.Task.ToString());

        var miner = VillainHero(MapLayout.MicroMine + new V3(30f, 0f, 0f));
        miner.HasStorage = false;
        miner.MicroVeins.Add(new Vein(MapLayout.MicroMine + MapLayout.MicroMineStone[0], 1.5f));
        miner.MicroVeins.Add(new Vein(new V3(0f, 0f, 0f), 1.5f));
        var walk = HeroBrain.Decide(miner);
        miner.At = MapLayout.MicroMine + MapLayout.MicroMineStone[0] + new V3(3f, 0f, 0f);
        var dig = HeroBrain.Decide(miner);
        miner.HasStorage = true;
        var built = HeroBrain.Decide(miner);
        Check(walk.Task == HeroTask.Dig && walk.Walk && dig.Attack && dig.Weapon == WeaponKind.Hammer && built.Task == HeroTask.Follow,
            "злодей без склада копает микро-шахту молотом (досягаемость с радиусом камня); со складом — нет",
            walk.Task + " → " + dig.Task + ", со складом " + built.Task);

        var elfHome = Factions.Spawn[(int)Faction.Elves];
        var elf = new HeroView { Side = Faction.Elves, At = elfHome, ElfHouseLimit = 3, Weapon = WeaponKind.Axe };
        elf.Stock = Res.Fit(Res.BuildingCost(BuildingKind.ElfHouse));
        var house = HeroBrain.Decide(elf);
        elf.ElfSpotBuildable = spot => spot.FlatDistance(elfHome) > 40f;
        var outer = HeroBrain.Decide(elf);
        Check(house.Task == HeroTask.BuildElfHouse && house.Interact && Math.Abs(house.BuildAt.Value.FlatDistance(elfHome) - 32f) < 0.1f
            && outer.Walk && Math.Abs(outer.Goal.FlatDistance(elfHome) - 48f) < 0.1f,
            "эльф ставит дом на ближнем кольце у спавна, занято — на следующем", "кольцо " + outer.Goal.FlatDistance(elfHome).ToString("0"));

        var poor = new HeroView { Side = Faction.Elves, At = elfHome + new V3(140f, 0f, 0f), ElfHouseLimit = 3, Weapon = WeaponKind.Axe };
        poor.Trees.Add(new Vein(elfHome + new V3(150f, 0f, 0f), 1f));
        poor.Trees.Add(new Vein(elfHome + new V3(60f, 0f, 0f), 1f));
        var chop = HeroBrain.Decide(poor);
        poor.ElfHouses = 3;
        var full = HeroBrain.Decide(poor);
        Check(chop.Task == HeroTask.ChopTree && chop.Goal.FlatDistance(elfHome) < 61f && full.Task != HeroTask.ChopTree,
            "на дом не хватает — эльф рубит свой лес (дальний не трогает); домов под потолок — не рубит",
            "рубит у " + chop.Goal + ", при полном потолке " + full.Task);

        var smith = VillainHero(at);
        smith.Forge = new V3(40f, 0f, 0f);
        smith.NextGearCost = new[] { 10, 0, 0, 10 };
        smith.Stock = new[] { 20, 0, 0, 20 };
        var toForge = HeroBrain.Decide(smith);
        smith.AtForge = true;
        var forge = HeroBrain.Decide(smith);
        smith.Stock = new[] { 15, 0, 0, 20 };
        var spare = HeroBrain.Decide(smith);
        Check(toForge.Task == HeroTask.ForgeGear && toForge.Walk && forge.Interact && spare.Task == HeroTask.Follow,
            "лишнее вдвое против цены — в кузню; меньше — добро остаётся на стройку", spare.Task.ToString());

        var hurt = VillainHero(at);
        hurt.Health = 35f;
        hurt.PotionsHeal = 1;
        hurt.Others.Add(new SidedPoint(new V3(15f, 0f, 0f), (int)Faction.Guard));
        var panic = HeroBrain.Decide(hurt);
        var crowd = VillainHero(at);
        for (int i = 0; i < 3; i++) crowd.Others.Add(new SidedPoint(new V3(15f + i * 2f, 0f, 0f), (int)Faction.Elves));
        var curse = HeroBrain.Decide(crowd);
        Check(panic.UsePotion && panic.Spell == AbilityKind.Paralysis && curse.Spell == AbilityKind.Wither,
            "ранен — пьёт зелье и парализует; кучка из трёх — увядание", panic.Spell + ", " + curse.Spell);

        var carter = VillainHero(at);
        carter.OwnCart = new V3(0f, 0f, 5f);
        carter.Others.Add(new SidedPoint(new V3(3f, 0f, 0f), (int)Faction.Guard));
        Check(!HeroBrain.Decide(carter).Attack,
            "у своего обоза молотом не машет: удар задел бы лошадей", "обоз в 5 м");

        var buildings = new List<KeyValuePair<BuildingKind, V3>>
        {
            new KeyValuePair<BuildingKind, V3>(BuildingKind.Storage, new V3(0f, 0f, 10f)),
            new KeyValuePair<BuildingKind, V3>(BuildingKind.Farm, new V3(0f, 0f, 40f)),
        };
        bool blocked = Geometry.BuildingBetween(new V3(0f, 0f, 0f), new V3(0f, 0f, 20f), buildings);
        bool inside = Geometry.BuildingBetween(new V3(0f, 0f, 0f), new V3(0f, 0f, 10f), buildings);
        bool beside = Geometry.BuildingBetween(new V3(20f, 0f, 0f), new V3(20f, 0f, 20f), buildings);
        bool field = Geometry.BuildingBetween(new V3(0f, 0f, 30f), new V3(0f, 0f, 50f), buildings);
        Check(blocked && !inside && !beside && !field,
            "постройка на прямой — обходить по пути; к самой постройке и через поле — напрямик",
            "насквозь " + blocked + ", к ней " + inside + ", мимо " + beside + ", поле " + field);
    }

    static void RespawnRules()
    {
        Check(Respawn.ElfHouseLimit(0) == 5 && Respawn.ElfHouseLimit(3) == 15 && Respawn.ElfHousesStart.Length == 3,
            "эльфам — пять домов на игрока (за пустую сторону — как на одного), три стоят со старта",
            "потолок при трёх " + Respawn.ElfHouseLimit(3));

        bool wait = Respawn.Verdict(Faction.Elves, false, 0, false) == RespawnVerdict.WaitForHouse;
        bool gone = Respawn.Verdict(Faction.Elves, false, 0, true) == RespawnVerdict.Never;
        bool leader = Respawn.Verdict(Faction.Guard, true, 0, false) == RespawnVerdict.Never;
        bool guard = Respawn.Verdict(Faction.Guard, false, 0, false) == RespawnVerdict.Now;
        Check(wait && gone && leader && guard && Respawn.Verdict(Faction.Elves, false, 1, false) == RespawnVerdict.Now,
            "эльф без домов ждёт отстройки, при выбывших эльфах — не встаёт; вожак пал насовсем",
            "ждёт " + wait + ", выбыли " + gone + ", вожак " + leader);

        var houses = new List<V3> { new V3(-255f, 0f, -300f), new V3(-310f, 0f, -343.9f) };
        var point = Respawn.SpawnPoint(Faction.Elves, 1, true, new V3(-300f, 0f, -350f), houses);
        float back = Res.BuildingSize(BuildingKind.ElfHouse).Z * 0.5f + 3f;
        Check(Math.Abs(point.X - (-310f + Respawn.HouseSlotStep)) < 0.01f && Math.Abs(point.Z - (-343.9f - back)) < 0.01f,
            "эльф встаёт у ближайшего достроенного дома, с северной стороны", "точка " + point);

        var start = Respawn.SpawnPoint(Faction.Elves, 7, false, new V3(0f, 0f, 0f), houses);
        var none = Respawn.SpawnPoint(Faction.Elves, 0, true, new V3(0f, 0f, 0f), new List<V3>());
        var spawn = Factions.Spawn[(int)Faction.Elves];
        Check(Math.Abs(start.X - (spawn.X + Respawn.SlotStep)) < 0.01f && none.Distance(spawn) < 0.01f,
            "в партию входят у точки стороны (место по остатку от шести), без домов — там же", "слот 7 — " + start);
    }

    static void CommanderRules()
    {
        var post = new CommanderPost();
        bool talk = post.InRange(CommanderPost.Position + new V3(5f, -6f, 3f));
        post.OnDied();
        bool silent = !post.InRange(CommanderPost.Position);
        bool back = false;
        float waited = 0f;
        while (!back && waited < 1000f)
        {
            back = post.Tick(1f);
            waited += 1f;
        }
        Check(talk && silent && back && Math.Abs(waited - CommanderPost.RespawnDelay) < 1.1f && post.OnDuty,
            "распорядитель убиваем, но через три минуты снова на посту; павшему не доложишь",
            "вернулся через " + waited + " с");

        var robbed = new CommanderPost();
        var near = new List<KeyValuePair<int, V3>>
        {
            new KeyValuePair<int, V3>(1, new V3(10f, 0f, 0f)),
            new KeyValuePair<int, V3>(2, new V3(60f, 0f, 0f)),
        };
        robbed.OnCaravanLost(new V3(0f, 0f, 0f), near);
        Check(robbed.IsRobber(1) && !robbed.IsRobber(2) && robbed.AnyRobberAlive(id => id == 1) && !robbed.AnyRobberAlive(id => false),
            "грабители — враги в 30 м от ограбленного обоза; погоня — пока жив хоть один", "дальний не записан");

        var crowd = new List<KeyValuePair<int, V3>>();
        for (int i = 0; i < 20; i++) crowd.Add(new KeyValuePair<int, V3>(100 + i, new V3(i, 0f, 0f)));
        robbed.OnCaravanLost(new V3(0f, 0f, 0f), crowd);
        Check(!robbed.IsRobber(1) && !robbed.IsRobber(107) && robbed.IsRobber(108) && robbed.IsRobber(119),
            "память о грабителях — последние двенадцать", "старые забыты");
    }

    static void PlacementRules()
    {
        var storage = new V3(0f, 0f, 0f);
        var standing = new List<KeyValuePair<BuildingKind, V3>> { new KeyValuePair<BuildingKind, V3>(BuildingKind.Storage, storage) };
        var size = Res.BuildingSize(BuildingKind.Storage);
        float snug = size.X + 3f;
        bool touching = Placement.Clear(new V3(snug - 0.5f, 0f, 0f), BuildingKind.Storage, standing);
        bool spaced = Placement.Clear(new V3(snug + 0.5f, 0f, 0f), BuildingKind.Storage, standing);
        Check(!touching && spaced, "между постройками зазор 3 м: проход между домами не закрыть",
            "впритык " + touching + ", с зазором " + spaced);

        bool flat = Placement.GroundFits(new float?[] { 0f, 1f, 2f, 6.5f, 3f });
        bool cliff = Placement.GroundFits(new float?[] { 0f, 1f, 2f, 7.5f, 3f });
        bool edge = Placement.GroundFits(new float?[] { 0f, null, 0f, 0f, 0f });
        Check(flat && !cliff && !edge, "земля под пятном — не круче ступеньки в 7 м и не за краем мира",
            "склон " + flat + ", обрыв " + cliff + ", край " + edge);

        var relief = Relief.ForMap();
        var none = new List<KeyValuePair<BuildingKind, V3>>();
        bool home = Placement.Buildable(MapLayout.ZoneCenters[(int)Zone.Villain], BuildingKind.Storage, relief, none);
        bool outside = Placement.Buildable(new V3(598f, 0f, 150f), BuildingKind.Storage, relief, none);
        Check(home && !outside, "в зоне злодея ставить можно, за краем мира — нет", "зона " + home + ", край " + outside);
    }

    static List<V3> Road()
    {
        return new List<V3> { new V3(0f, 0f, 0f), new V3(0f, 0f, 100f), new V3(0f, 0f, 200f) };
    }

    static int[] Iron(int amount)
    {
        var cargo = Res.Empty();
        cargo[(int)ResourceKind.Iron] = amount;
        return cargo;
    }

    static void TripRules()
    {
        var trip = new CaravanTrip(Faction.Villain, 1, Road(), 2);
        var wallet = new Wallet();
        wallet.Stored.Capacity = 500;
        var none = new List<KeyValuePair<BuildingKind, V3>>();
        var dock = new List<KeyValuePair<BuildingKind, V3>> { new KeyValuePair<BuildingKind, V3>(BuildingKind.Storage, new V3(0f, 0f, 0f)) };
        var events = new List<TripEvent>();
        float t = 0f;
        while (trip.State != CaravanState.Finished && t < 200f)
        {
            var e = trip.Tick(0.1f, false, dock, at => at.FlatDistance(new V3(0f, 0f, 200f)) < 10f ? Iron(50) : null, wallet);
            if (e != TripEvent.None) events.Add(e);
            t += 0.1f;
        }
        float expected = 400f / CaravanRules.SpeedFor(2) + 2f * CaravanRules.LoadSeconds;
        Check(trip.State == CaravanState.Finished && wallet.Stored.GetAmount(ResourceKind.Iron) == 50
            && events.Count == 3 && events[0] == TripEvent.Loaded && Math.Abs(t - expected) < 2f,
            "обоз едет к шахте, грузится, возвращается тем же путём и выгружает на склад (свой склад в конце пути — не помеха)",
            "рейс " + t.ToString("0.0") + " с при расчётных " + expected.ToString("0.0"));

        var stopped = new CaravanTrip(Faction.Villain, 1, Road(), 2);
        for (int i = 0; i < 20; i++) stopped.Tick(0.1f, true, none, null, wallet);
        Check(stopped.Halted && stopped.Position.Distance(new V3(0f, 0f, 0f)) < 0.01f,
            "враг рядом — обоз встаёт", "сдвинулся на " + stopped.Position.Distance(new V3(0f, 0f, 0f)));

        var full = new CaravanTrip(Faction.Villain, 1, Road(), 6);
        var tight = new Wallet();
        tight.Stored.Capacity = 30;
        int alarms = 0;
        for (int i = 0; i < 1000 && full.State != CaravanState.Finished; i++)
        {
            if (full.Tick(0.1f, false, none, at => Iron(50), tight) == TripEvent.StorageFull) alarms++;
            if (i == 800) tight.Stored.Capacity = 100;
        }
        Check(alarms == 1 && full.State == CaravanState.Finished && tight.Stored.GetAmount(ResourceKind.Iron) == 50,
            "склад полон — обоз ждёт у склада с грузом, оповещает один раз и выгружает, когда место появилось",
            "оповещений " + alarms);

        var detour = new CaravanTrip(Faction.Villain, 1, Road(), 2);
        var house = new List<KeyValuePair<BuildingKind, V3>> { new KeyValuePair<BuildingKind, V3>(BuildingKind.Storage, new V3(0f, 0f, 100f)) };
        var size = Res.BuildingSize(BuildingKind.Storage);
        float closest = float.MaxValue;
        for (int i = 0; i < 1000 && detour.State != CaravanState.Finished; i++)
        {
            detour.Tick(0.1f, false, house, null, null);
            closest = Math.Min(closest, CaravanTrip.BoxGap(detour.Position, new V3(0f, 0f, 100f), size.X * 0.5f, size.Z * 0.5f));
        }
        Check(detour.State == CaravanState.Finished && closest > 0f,
            "дом, поставленный на линии маршрута, обоз объезжает туда и обратно, точку внутри пропускает",
            "ближе всего к стене " + closest.ToString("0.0") + " м");

        var harness = new CaravanTrip(Faction.Guard, 0, Road(), 2);
        harness.HurtHarness(50f);
        int afterFirst = harness.Horses;
        harness.HurtHarness(20f);
        int afterSecond = harness.Horses;
        int early = harness.CaptureHorses();
        harness.HurtHarness(60f);
        Check(afterFirst == 2 && afterSecond == 1 && early == 0 && harness.Horses == 0 && harness.Halted && harness.SpeedNow == 0f,
            "лошади гибнут по одной с общего запаса; без лошадей обоз встал; у едущего не увести",
            afterFirst + " → " + afterSecond + " → " + harness.Horses);

        var robbed = new CaravanTrip(Faction.Guard, 0, Road(), 3);
        robbed.Tick(0.1f, true, none, null, wallet);
        Check(robbed.CaptureHorses() == 3 && robbed.Horses == 0, "у стоящего обоза уводят всю упряжку", "уведено 3");

        var ahead = new CaravanTrip(Faction.Villain, 1, Road(), 2);
        int outbound = ahead.PathAhead().Count;
        ahead.Redirect(Faction.Guard, 2, new List<V3> { new V3(0f, 0f, 200f), new V3(300f, 0f, -200f) });
        var home = ahead.PathAhead();
        Check(outbound == 5 && ahead.State == CaravanState.ToHome && ahead.Side == Faction.Guard
            && home.Count == 2 && home[home.Count - 1].Distance(new V3(0f, 0f, 200f)) < 0.01f,
            "путь вперёд — туда и обратно; перехваченный обоз едет к складу перехватчика", "впереди " + outbound + " точек");
    }

    static WorkSite Site(int id, SiteKind kind, Faction side, V3 at, float body, ResourceKind resource)
    {
        return new WorkSite { Id = id, Kind = kind, Side = side, At = at, Body = body, Resource = resource, Dock = at };
    }

    static void LabourerRules()
    {
        var home = new V3(0f, 0f, 0f);
        var tree = Site(1, SiteKind.Harvestable, Faction.Villain, new V3(40f, 0f, 0f), 1f, ResourceKind.Wood);
        var rock = Site(2, SiteKind.Harvestable, Faction.Villain, new V3(10f, 0f, 0f), 3f, ResourceKind.Stone);
        var ours = Site(3, SiteKind.Storage, Faction.Villain, new V3(0f, 0f, 30f), 6f, ResourceKind.Wood);
        var theirs = Site(4, SiteKind.Storage, Faction.Guard, new V3(35f, 0f, 0f), 6f, ResourceKind.Wood);
        var view = new LabourerView { At = home, Home = home };
        view.Sites.AddRange(new[] { tree, rock, ours, theirs });

        var jack = new LabourerBrain(Faction.Villain, LabourerRole.Lumberjack);
        var walk = jack.Tick(0.1f, view);
        view.At = new V3(35f, 0f, 0f);
        var chop = jack.Tick(0.1f, view);
        Check(walk.Site == tree && walk.Goal.Distance(tree.At) < 0.01f && chop.Action == LabourAction.Harvest,
            "лесоруб идёт к ближайшему дереву (камень не его) и рубит с 4.5 м плюс толщина ствола",
            "ближе камень, а цель — " + walk.Site.Resource);

        for (int i = 0; i < 6; i++) jack.Harvested(ResourceKind.Wood);
        var carry = jack.Tick(0.1f, view);
        view.At = ours.At + new V3(8f, 0f, 0f);
        var hand = jack.Tick(0.1f, view);
        var wallet = new Wallet();
        wallet.Stored.Capacity = 20;
        int brought = jack.Unload(wallet);
        Check(carry.Goal.Distance(ours.At) < 0.01f && hand.Action == LabourAction.Deliver && brought == 30
            && wallet.Stored.GetAmount(ResourceKind.Wood) == 20 && wallet.Carried.GetAmount(ResourceKind.Wood) == 10 && jack.Carrying == 0,
            "полная ноша (30) — на ближайший свой склад, чужой не в счёт; не влезшее — в казну при себе",
            "склад " + wallet.Stored.GetAmount(ResourceKind.Wood) + ", при себе " + wallet.Carried.GetAmount(ResourceKind.Wood));

        var scared = new LabourerView { At = new V3(10f, 0f, 0f), Home = new V3(10f, 0f, -100f) };
        scared.Others.Add(new SidedPoint(new V3(8f, 0f, 0f), (int)Faction.Villain));
        scared.Others.Add(new SidedPoint(new V3(20f, 0f, 0f), (int)Faction.Elves));
        var flee = new LabourerBrain(Faction.Villain, LabourerRole.Lumberjack).Tick(0.1f, scared);
        var run = (flee.Goal - scared.At).Flat();
        Check(flee.Fleeing && Math.Abs(run.Length() - LabourerStats.FleeRadius) < 0.01f && run.X < 0f && run.Z < 0f,
            "враг в 18 м — батрак бежит: наполовину прочь, наполовину к дому; свой не пугает", "бежит на " + run);

        var mine = Site(9, SiteKind.Mine, Faction.Villain, new V3(-167f, 0f, -158f), 17f, ResourceKind.Iron);
        mine.Dock = new V3(-150f, 0f, -140f);
        var pit = new LabourerView { At = home, Home = home, SideMine = mine };
        pit.Sites.Add(rock);
        var miner = new LabourerBrain(Faction.Villain, LabourerRole.Miner);
        var go = miner.Tick(0.1f, pit);
        pit.At = mine.Dock + new V3(15f, 0f, 0f);
        var short_ = miner.Tick(0.1f, pit);
        pit.At = mine.Dock + new V3(8f, 0f, 0f);
        var dig = miner.Tick(0.1f, pit);
        Check(go.Goal.Distance(mine.Dock) < 0.01f && short_.Action == LabourAction.None && dig.Action == LabourAction.Dig && miner.Carrying == 0,
            "шахтёр копает в 9 м от входа шахты своей стороны, мимо камня, и руду не носит — её везёт обоз",
            "цель " + go.Goal);

        var farm = Site(5, SiteKind.Farm, Faction.Villain, new V3(0f, 0f, -20f), 10f, ResourceKind.Food);
        var field = new LabourerView { At = farm.At, Home = home };
        field.Sites.AddRange(new[] { farm, ours });
        var farmer = new LabourerBrain(Faction.Villain, LabourerRole.Farmer);
        var take = farmer.Tick(0.1f, field);
        var crop = Res.Empty();
        crop[(int)ResourceKind.Food] = 6;
        farmer.Took(crop);
        farmer.Tick(1.3f, field);
        farmer.Took(Res.Empty());
        var bring = farmer.Tick(0.1f, field);
        Check(take.Action == LabourAction.Take && bring.Goal.Distance(ours.At) < 0.01f,
            "фермер берёт еду с поля; поле пустое, а в руках есть — несёт на склад", "несёт " + farmer.Carrying);

        int fed = 0, starving = 0;
        var worker = new LabourerBrain(Faction.Villain, LabourerRole.Lumberjack);
        var worker2 = new LabourerBrain(Faction.Villain, LabourerRole.Lumberjack);
        var atTree = new LabourerView { At = tree.At, Home = home };
        atTree.Sites.Add(tree);
        var hungry = new LabourerView { At = tree.At, Home = home, Hungry = true };
        hungry.Sites.Add(tree);
        for (int i = 0; i < 120; i++)
        {
            if (worker.Tick(0.1f, atTree).Action == LabourAction.Harvest) fed++;
            if (worker2.Tick(0.1f, hungry).Action == LabourAction.Harvest) starving++;
        }
        Check(fed == 10 && starving == 5, "голодный батрак работает вдвое медленнее", "за 12 с: сытый " + fed + ", голодный " + starving);

        var site = Site(6, SiteKind.Construction, Faction.Villain, new V3(5f, 0f, 0f), 6f, ResourceKind.Wood);
        var yard = new LabourerView { At = home, Home = home };
        yard.Sites.Add(site);
        var build = new LabourerBrain(Faction.Villain, LabourerRole.Builder).Tick(0.1f, yard);
        var post = new LabourerView { At = new V3(5f, 0f, 5f), Home = home };
        var militia = new LabourerBrain(Faction.Villain, LabourerRole.Militia).Tick(0.1f, post);
        Check(build.Action == LabourAction.Build && militia.Action == LabourAction.None && militia.Goal.Distance(post.At) < 0.01f,
            "строитель стоит у стройки; ополченца ведёт отряд, а не работа", build.Action.ToString());

        var fell = new LabourerBrain(Faction.Villain, LabourerRole.Lumberjack);
        var two = new LabourerView { At = home, Home = home };
        var near = Site(7, SiteKind.Harvestable, Faction.Villain, new V3(10f, 0f, 0f), 1f, ResourceKind.Wood);
        var far = Site(8, SiteKind.Harvestable, Faction.Villain, new V3(60f, 0f, 0f), 1f, ResourceKind.Wood);
        two.Sites.AddRange(new[] { near, far });
        fell.Tick(0.1f, two);
        two.Sites.Remove(near);
        var next = fell.Tick(0.1f, two);
        Check(next.Site == far, "дерево повалили — батрак сразу идёт к другому", "цель " + next.Goal);
    }

    static void UnitRules()
    {
        var here = new V3(0f, 0f, 0f);
        var sword = new UnitBrain(UnitKind.Swordsman, (int)Faction.Guard);
        var bow = new UnitBrain(UnitKind.Archer, (int)Faction.Guard);
        var around = new List<Sighting>
        {
            new Sighting(1, new V3(16f, 0f, 0f), (int)Faction.Villain, null),
            new Sighting(2, new V3(3f, 0f, 0f), (int)Faction.Guard, null),
            new Sighting(3, new V3(0f, 0f, 5f), -1, null),
        };
        var none = sword.FindTarget(here, around);
        var shot = bow.FindTarget(here, around);
        around.Add(new Sighting(4, new V3(12f, 0f, 0f), (int)Faction.Villain, null));
        var near = sword.FindTarget(here, around);
        Check(!none.HasValue && shot.HasValue && shot.Value.Id == 1 && near.Value.Id == 4,
            "мечник вступает с 14 м, лучник видит на 32; своих и неизвестных не бьют",
            "лучник целит " + shot.Value.Id + ", мечник " + near.Value.Id);

        var led = new UnitBrain(UnitKind.Swordsman, (int)Faction.Guard)
            { AiLed = true, AiAnchor = new V3(-20f, 0f, 0f), Leash = AiStats.MarchLeash };
        var far = new List<Sighting> { new Sighting(5, new V3(10f, 0f, 0f), (int)Faction.Villain, null) };
        var loose = new UnitBrain(UnitKind.Swordsman, (int)Faction.Guard);
        Check(!led.Engage(here, far).HasValue && loose.Engage(here, far).HasValue,
            "на поводке у якоря отряда за врагом дальше 26 м от якоря не идёт; без поводка — идёт", "якорь в 30 м от врага");

        var archer = new UnitBrain(UnitKind.Archer, (int)Faction.Guard) { AiLed = true, AiAnchor = new V3(100f, 0f, 0f), AiYaw = (float)(Math.PI / 2), AiFormation = FormationKind.Line };
        var spot = archer.IdleDestination(here, null, 0f, null);
        var slot0 = Formations.SlotOffset(FormationKind.Line, 0);
        Check(Math.Abs(spot.X - (100f + slot0.Z + UnitStats.ArcherRear)) < 0.01f && Math.Abs(spot.Z + slot0.X) < 0.01f,
            "без цели — на своё место в строю за якорем, развёрнутым по курсу; лучник на 7 м позади",
            "место " + spot);

        var homebody = new UnitBrain(UnitKind.Swordsman, (int)Faction.Guard) { Home = new V3(5f, 0f, 5f), Leash = 90f };
        var idle = new UnitBrain(UnitKind.Swordsman, (int)Faction.Guard);
        Check(homebody.IdleDestination(here, null, 0f, null).Distance(homebody.Home) < 0.01f
            && idle.IdleDestination(new V3(7f, 0f, 7f), null, 0f, null).Distance(new V3(7f, 0f, 7f)) < 0.01f,
            "гарнизон без цели возвращается домой; боец без дома и поводка стоит где стоит", "дом " + homebody.Home);

        var storage = new Sighting(6, here, (int)Faction.Villain, BuildingKind.Storage);
        var size = Res.BuildingSize(BuildingKind.Storage);
        Check(Math.Abs(sword.ReachOf(storage) - (UnitStats.StrikeRange + Math.Max(size.X, size.Z) * 0.5f)) < 0.01f
            && bow.ReachOf(storage) == UnitStats.ArcherRange,
            "по постройке бьют с её края, а не из центра; лучник стреляет с 24 м", "досягаемость " + sword.ReachOf(storage));

        bool first = bow.TryStrike(true);
        bool again = bow.TryStrike(true);
        bow.Tick(1.01f);
        bool later = bow.TryStrike(true);
        bool maimed = sword.TryStrike(UnitBrain.ArmsWork(false, true, false)) && !UnitBrain.ArmsWork(true, true, false);
        Check(first && !again && later && maimed && UnitStats.StrikeDamage(UnitKind.Archer) == Weapons.Damage[(int)WeaponKind.Bow],
            "лучник бьёт стрелой лука (30) раз в секунду; мечнику хватит руки, лучнику нужны обе",
            "урон лучника " + UnitStats.StrikeDamage(UnitKind.Archer));

        var charmed = new UnitBrain(UnitKind.Swordsman, (int)Faction.Guard) { AiLed = true, Leash = 26f };
        charmed.Charm((int)Faction.Villain, Abilities.ParalysisCharm, new V3(3f, 0f, 3f));
        bool turned = charmed.Side == (int)Faction.Villain && !charmed.AiLed && charmed.Leash == 0f;
        for (int i = 0; i < 90; i++) charmed.Tick(0.1f);
        Check(turned && charmed.Side == (int)Faction.Guard && !charmed.Charmed,
            "очарованный боец воюет за злодея 8 с, потом возвращается к своим", "сторона " + charmed.Side);

        var push = UnitBrain.Separation(here, new[] { new V3(0f, 0f, -1f), new V3(5f, 0f, 0f) });
        var steer = UnitBrain.Steer(new V3(0f, 0f, -5f), push);
        var fast = UnitBrain.Steer(new V3(0f, 0f, -8f), new V3(6f, 0f, 0f));
        Check(push.Z > 0f && Math.Abs(steer.Z + 5f) < 0.01f && Math.Abs(fast.Length() - UnitStats.MaxFlatSpeed) < 0.01f
            && Math.Abs(UnitBrain.WoundSpeedScale(2) * UnitStats.BaseSpeed - BodyState.CrawlSpeedBoth) < 0.01f,
            "сосед вплотную расталкивает, но не тормозит идущего вперёд; итог не быстрее 9 м/с; без ног — ползком",
            "толчок " + push + ", ход " + steer);
    }

    static void ForestRules()
    {
        var forest = Forest.ForMap();
        var centre = MapLayout.ZoneCenters[(int)Zone.Elves];
        int inClearing = 0, inMine = 0, outside = 0, woods = 0;
        for (int i = 0; i < forest.Count; i++)
        {
            var p = forest.Positions[i];
            float r = p.FlatDistance(centre);
            if (r < Forest.Clearing) inClearing++;
            if (r > MapLayout.ZoneHalf - 30f) outside++;
            if (r <= AiStats.ElfWoods) woods++;
            foreach (var mine in MapLayout.Mines)
                if (p.FlatDistance(mine.At) < MapLayout.MineClearing) inMine++;
        }
        Check(forest.Count == Forest.TreeCount && inClearing == 0 && inMine == 0 && outside == 0,
            "лес эльфов: 1700 деревьев кольцом, поселение и поляны шахт пусты, за зону не выходит",
            "деревьев " + forest.Count + ", на полянах " + (inClearing + inMine));
        Check(woods > 50, "у поселения (110 м) есть свой лес: герою-эльфу есть что рубить на дома", "деревьев " + woods);

        var twin = Forest.ForMap();
        Check(twin.Positions[777].Distance(forest.Positions[777]) < 0.001f && twin.Scales[1234] == forest.Scales[1234],
            "лес одинаков у хоста и клиента: дерево адресуется номером", "дерево 777 — " + forest.Positions[777]);

        int left = 0;
        for (int i = 0; i < Res.SourceHits; i++) left = forest.Hit(10);
        forest.Fell(10);
        Check(left == 0 && forest.IsFelled(10) && forest.Hit(10) == -1 && forest.FelledIndices().Contains(10)
            && forest.Nearest(forest.Positions[10], 0.5f) != 10,
            "дерево валят за шесть ударов; поваленное не бьют и не находят, опоздавшему шлют список", "поваленных " + forest.FelledIndices().Count);

        var tree = forest.Positions[20];
        var from = tree + new V3(80f, 0f, 0f);
        var fresh = new HashSet<int>();
        forest.CollectAround(from, Forest.SolidRadius, Forest.SolidRelease, null, fresh);
        var kept = new HashSet<int>();
        forest.CollectAround(from, Forest.SolidRadius, Forest.SolidRelease, new HashSet<int> { 20 }, kept);
        Check(!fresh.Contains(20) && kept.Contains(20),
            "ствол в 80 м твердеет только с 70 м, а твёрдым остаётся до 88 — на границе не мигает", "взято " + kept.Count);
    }
}
