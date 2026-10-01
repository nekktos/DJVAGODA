// Режим игрока (перенос world.gd: strategy_mode): бой из-за плеча или вид
// сверху. Сверху — стройка, обозы, приказы; персонаж стоит, мышь свободна, а
// те же цифры значат постройки, а не оружие (раскладка KeyActions: группа
// Strategy). Режим — на этой машине: у каждого игрока свой.
namespace DjvaGoda.Game
{
    public static class GameMode
    {
        public static bool Strategy;
    }
}
