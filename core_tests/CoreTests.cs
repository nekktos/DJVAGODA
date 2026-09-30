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
    const int Expected = 17;
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
