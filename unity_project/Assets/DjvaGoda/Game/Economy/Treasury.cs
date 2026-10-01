// Казна сторон (перенос economy/treasury.gd): запас — у СТОРОНЫ, а не у
// персонажа. Склад переживает смерть персонажа, и все игроки стороны (и её ИИ)
// видят один кошелёк. Меняет только хост; клиентам её везёт MatchNet.
//
// Стартовый запас — ПРИ СЕБЕ, а не в складе: склада на старте нет ни у кого,
// его ещё надо построить, и до тех пор запас под риском (GDD 4.1).
using DjvaGoda.Core;

namespace DjvaGoda.Game
{
    public static class Treasury
    {
        static readonly Wallet[] Wallets = { new Wallet(), new Wallet(), new Wallet() };

        public static Wallet Of(Faction side) { return Wallets[(int)side]; }
        public static Wallet Of(int side) { return Wallets[Res.Clamp(side, 0, Factions.Count - 1)]; }

        /// Разложить стартовый запас заново (начало партии).
        public static void Reset()
        {
            for (int side = 0; side < Factions.Count; side++)
            {
                var wallet = Wallets[side];
                wallet.Carried.Amounts = Res.Fit(Factions.StartingResources[side]);
                wallet.Carried.Capacity = Factions.StartingCapacity[side];
                wallet.Stored.Amounts = Res.Empty();
                wallet.Stored.Capacity = 0;
                wallet.Horses = 0;
                wallet.HorsesOut = 0;
            }
        }
    }
}
