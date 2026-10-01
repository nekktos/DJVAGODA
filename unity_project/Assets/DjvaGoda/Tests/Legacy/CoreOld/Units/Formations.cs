// Строи отряда: форма и боевые модификаторы (перенос formations.gd).
namespace DjvaGoda.CoreOld
{
    public enum FormationKind { Line, ShieldWall, Column, Loose }

    public static class Formations
    {
        public static readonly string[] Names = { "шеренга", "стена щитов", "колонна", "рассыпной строй" };
        static readonly float[] DamageTaken = { 1f, 0.6f, 1.15f, 1f };
        static readonly float[] AoeTaken = { 1f, 1.1f, 1.25f, 0.35f };
        static readonly float[] SpeedScaleTable = { 1f, 0.6f, 1.3f, 1.05f };
        static readonly float[] SpacingX = { 2.2f, 1.3f, 2.2f, 4.6f };
        static readonly float[] SpacingZ = { 2.4f, 1.6f, 2.6f, 4.2f };
        static readonly int[] RankWidth = { 8, 8, 2, 4 };
        public const float FrontGap = 3.5f;

        /// Смещение места в строю от командира: X — вбок, Z — назад.
        public static V3 SlotOffset(FormationKind kind, int index)
        {
            int k = (int)kind;
            int width = RankWidth[k];
            int row = index / width;
            int column = index % width;
            float x = (column - (width - 1) * 0.5f) * SpacingX[k];
            float z = FrontGap + row * SpacingZ[k];
            if (kind == FormationKind.Loose && row % 2 == 1) x += SpacingX[k] * 0.5f;
            return new V3(x, 0f, z);
        }

        public static float DamageScale(FormationKind kind, bool aoe)
        {
            return aoe ? AoeTaken[(int)kind] : DamageTaken[(int)kind];
        }

        public static float SpeedScale(FormationKind kind)
        {
            return SpeedScaleTable[(int)kind];
        }
    }
}
