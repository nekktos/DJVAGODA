// Переход ядра на оси Unity: мир обязан стать ТОЧНЫМ зеркалом прежнего (z → −z,
// yaw → −yaw). Старое ядро — снимок в Tests/Legacy (DjvaGoda.CoreOld); после
// перехода снимок и эта сверка удаляются.
using System;
using NUnit.Framework;
using New = DjvaGoda.Core;
using Old = DjvaGoda.CoreOld;

public class AxesMirrorTests
{
    const float Eps = 1e-3f;

    static void Same(Old.V3 old, New.V3 now, string what)
    {
        Assert.That(Math.Abs(now.X - old.X) < Eps && Math.Abs(now.Y - old.Y) < Eps && Math.Abs(now.Z + old.Z) < Eps,
            what + ": было (" + old.X + ", " + old.Y + ", " + old.Z + "), стало (" + now.X + ", " + now.Y + ", " + now.Z + ")");
    }

    static float Wrap(float a)
    {
        double t = a % (2 * Math.PI);
        if (t > Math.PI) t -= 2 * Math.PI;
        if (t < -Math.PI) t += 2 * Math.PI;
        return (float)t;
    }

    [Test]
    public void MapPointsAreMirrored()
    {
        for (int i = 0; i < 3; i++) Same(Old.Factions.Spawn[i], New.Factions.Spawn[i], "точка стороны " + i);
        for (int i = 0; i < 4; i++) Same(Old.MapLayout.ZoneCenters[i], New.MapLayout.ZoneCenters[i], "зона " + i);
        for (int i = 0; i < Old.MapLayout.Mines.Length; i++)
        {
            Same(Old.MapLayout.Mines[i].At, New.MapLayout.Mines[i].At, "шахта " + i);
            Same(Old.MapLayout.MineEntrance(Old.MapLayout.Mines[i].At), New.MapLayout.MineEntrance(New.MapLayout.Mines[i].At), "вход шахты " + i);
        }
        Same(Old.MapLayout.RampFoot, New.MapLayout.RampFoot, "подножие пандуса");
        Same(Old.MatchState.Palace, New.MatchState.Palace, "дворец");
        Same(Old.ElfTaskRecord.ElderPosition, New.ElfTaskRecord.ElderPosition, "старейшина");
        Same(Old.Orders.RaidPoint, New.Orders.RaidPoint, "точка набега");
    }

    [Test]
    public void ReliefIsMirrored()
    {
        var old = Old.Relief.ForMap();
        var now = New.Relief.ForMap();
        for (float x = -600f; x <= 600f; x += 37f)
            for (float z = -600f; z <= 600f; z += 41f)
                Assert.That(Math.Abs(now.Height(x, -z) - old.Height(x, z)), Is.LessThan(Eps), "высота в (" + x + ", " + z + ")");
    }

    [Test]
    public void ForestIsMirrored()
    {
        var old = Old.Forest.ForMap();
        var now = New.Forest.ForMap();
        Assert.That(now.Count, Is.EqualTo(old.Count));
        for (int i = 0; i < old.Count; i++)
        {
            Same(old.Positions[i], now.Positions[i], "дерево " + i);
            Assert.That(now.Scales[i], Is.EqualTo(old.Scales[i]));
        }
    }

    [Test]
    public void PlanIsMirrored()
    {
        var old = Old.WorldPlan.ForMap(Old.Relief.ForMap());
        var now = New.WorldPlan.ForMap(New.Relief.ForMap());
        Assert.That(now.Pieces.Count, Is.EqualTo(old.Pieces.Count));
        for (int i = 0; i < old.Pieces.Count; i++)
        {
            var a = old.Pieces[i];
            var b = now.Pieces[i];
            string what = "часть " + i + " (" + a.Group + ", " + a.Shape + ")";
            Same(a.Center, b.Center, what);
            Assert.That(Math.Abs(b.Size.X - a.Size.X) + Math.Abs(b.Size.Y - a.Size.Y) + Math.Abs(b.Size.Z - a.Size.Z), Is.LessThan(Eps), what + ": размер");
            Assert.That(Math.Abs(Wrap(b.Yaw + a.Yaw)), Is.LessThan(Eps), what + ": поворот " + a.Yaw + " → " + b.Yaw);
            Assert.That((int)b.Shape, Is.EqualTo((int)a.Shape), what);
            Assert.That(b.Material, Is.EqualTo(a.Material), what);
            Assert.That(b.ShapeSeed, Is.EqualTo(a.ShapeSeed), what);
        }
    }

    /// Повороты: смещение, повёрнутое в новом ядре на −yaw, — зеркало старого.
    [Test]
    public void RotationIsMirrored()
    {
        var offsets = new[] { new Old.V3(1f, 0f, 0f), new Old.V3(0.6f, 1.6f, -2f), new Old.V3(-3f, 0f, 5f) };
        foreach (var o in offsets)
            for (float yaw = -3f; yaw <= 3f; yaw += 0.7f)
                Same(Old.UnitBrain.Rotate(o, yaw), New.UnitBrain.Rotate(new New.V3(o.X, o.Y, -o.Z), -yaw), "поворот на " + yaw);
    }

    [Test]
    public void FormationSlotsAreMirrored()
    {
        foreach (Old.FormationKind kind in Enum.GetValues(typeof(Old.FormationKind)))
            for (int i = 0; i < 12; i++)
                Same(Old.Formations.SlotOffset(kind, i), New.Formations.SlotOffset((New.FormationKind)(int)kind, i), kind + " место " + i);
    }

    [Test]
    public void AimIsMirrored()
    {
        for (float yaw = -3f; yaw <= 3f; yaw += 0.9f)
            for (float pitch = -1f; pitch <= 1f; pitch += 0.5f)
                Same(Old.Aim.Straight(yaw, pitch), New.Aim.Straight(-yaw, pitch), "взгляд " + yaw + "/" + pitch);
    }

    /// Движение: тот же ввод при отражённом yaw даёт отражённую скорость.
    [Test]
    public void MotorIsMirrored()
    {
        var oldMotor = new Old.CharacterMotor();
        var newMotor = new New.CharacterMotor();
        var oldVitals = new Old.Vitals();
        var newVitals = new New.Vitals();
        var oldBody = new Old.BodyState();
        var newBody = new New.BodyState();
        float yaw = 0.8f;
        for (int step = 0; step < 30; step++)
        {
            float mx = step % 3 - 1f, my = step % 5 < 3 ? -1f : 0.5f;
            var a = oldMotor.Step(new Old.MotorInput { MoveX = mx, MoveY = my, Run = step > 10 }, 0.05f, yaw, true,
                Old.Faction.Elves, oldVitals, oldBody, false, false, false);
            var b = newMotor.Step(new New.MotorInput { MoveX = mx, MoveY = my, Run = step > 10 }, 0.05f, -yaw, true,
                New.Faction.Elves, newVitals, newBody, false, false, false);
            Same(a, b, "шаг " + step);
        }
    }
}
