// Голод артели (перенос world.gd::_tick_hunger).
//
// Раз в пять минут каждый батрак съедает свою долю из казны стороны. Кормим
// ВСЮ артель разом: не хватило на всех — не ест никто (иначе первые сыты, а
// последние мертвы в случайном порядке), и сторона узнаёт об этом одной
// строкой. Смерть — только с третьего пропуска: игрок, ушедший воевать, не
// должен вернуться на пепелище за то, что играл в другую часть игры.
namespace DjvaGoda.Core
{
    public struct FeedResult
    {
        /// Накормлены все.
        public bool Fed;
        /// Сколько батраков умерло от голода в эту кормёжку.
        public int Starved;
        /// Что сказать стороне; пусто — сказать нечего.
        public string Message;
    }

    public static class Hunger
    {
        /// Кормёжка. hunger — пропуски каждого батрака; меняется на месте.
        /// Умершие отмечаются значением >= Res.HungerFatal — убирает их мир.
        public static FeedResult Feed(Faction side, Wallet wallet, int[] hunger)
        {
            var result = new FeedResult();
            if (hunger == null || hunger.Length == 0) return result;
            var need = Res.Empty();
            need[(int)ResourceKind.Food] = hunger.Length * Res.FeedPerWorker;
            if (wallet.Spend(need))
            {
                for (int i = 0; i < hunger.Length; i++) hunger[i] = 0;
                result.Fed = true;
                return result;
            }
            for (int i = 0; i < hunger.Length; i++)
            {
                hunger[i] += 1;
                if (hunger[i] >= Res.HungerFatal) result.Starved++;
            }
            result.Message = "ГОЛОД: " + Factions.NameOf(side) + " — нечем кормить артель ("
                + hunger.Length + " ртов, надо " + need[(int)ResourceKind.Food] + " еды)";
            if (result.Starved > 0) result.Message += ". Умерло от голода: " + result.Starved;
            return result;
        }

        /// Голодный работает вдвое медленнее — беда видна делом.
        public static float WorkInterval(float baseInterval, int missedMeals)
        {
            return baseInterval * (missedMeals > 0 ? Res.HungerSlowdown : 1f);
        }
    }
}
