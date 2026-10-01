// Батрак: куда идти и что делать (перенос units/labourer.gd).
//
// Ополченец дерётся как боец — его ведёт отряд. Остальные: бегут от врага в
// 18 м (наполовину прочь, наполовину к дому), с полной ношей (30) несут её на
// ближайший достроенный склад своей стороны, иначе работают по роли: лесоруб
// рубит, шахтёр копает у входа шахты своей стороны (носить руками не нужно —
// руду везёт обоз), строитель стоит у стройки, фермер берёт еду с поля.
//
// Мозг чистый: мир — WorkSite'ы, работу исполняет Unity-слой и сообщает итог.
using System;
using System.Collections.Generic;

namespace DjvaGoda.Core
{
    public enum SiteKind { Harvestable, Farm, Construction, Mine, Storage }

    /// Место работы. Поле и склад — только достроенные; стройка — недостроенная.
    public class WorkSite
    {
        public int Id;
        public SiteKind Kind;
        public Faction Side;
        public V3 At;
        /// Радиус тела (камень, глыба) или полуразмер постройки — к центру не подойти.
        public float Body;
        public ResourceKind Resource;
        /// Шахта: куда встают копатели (вход).
        public V3 Dock;
    }

    public enum LabourAction { None, Harvest, Dig, Take, Build, Deliver }

    public struct LabourOrder
    {
        public V3 Goal;
        public LabourAction Action;
        public WorkSite Site;
        public bool Fleeing;
    }

    public class LabourerView
    {
        public V3 At;
        public V3 Home;
        public bool Hungry;
        /// Живые игроки и бойцы всех сторон рядом.
        public List<SidedPoint> Others = new List<SidedPoint>();
        public List<WorkSite> Sites = new List<WorkSite>();
        /// Шахта своей стороны (side_mine), если есть.
        public WorkSite SideMine;
    }

    public class LabourerBrain
    {
        public Faction Side;
        public LabourerRole Role;
        public int[] Load = Res.Empty();
        WorkSite _site;
        float _retarget;
        float _work;
        bool _tookNothing;
        V3? _drop;
        WorkSite _dropSite;

        public LabourerBrain(Faction side, LabourerRole role)
        {
            Side = side;
            Role = role;
        }

        public int Carrying
        {
            get
            {
                int total = 0;
                foreach (int value in Load) total += value;
                return total;
            }
        }

        public void SetRole(LabourerRole role)
        {
            Role = role;
            _site = null;
            _retarget = LabourerStats.RetargetInterval;
        }

        /// Такт хоста. Ополченца отсюда не ведут — его ведёт отряд: он стоит.
        public LabourOrder Tick(float delta, LabourerView view)
        {
            var stay = new LabourOrder { Goal = view.At };
            if (Role == LabourerRole.Militia) return stay;

            var danger = Threat(view);
            if (danger.HasValue)
            {
                _site = null;
                var away = (view.At - danger.Value).Flat();
                if (away.Length() < 0.1f) away = new V3(0f, 0f, 1f);
                var homeward = (view.Home - view.At).Flat();
                var run = (away.Normalized() * 0.5f + homeward.Normalized() * 0.5f).Normalized();
                return new LabourOrder { Goal = view.At + run * LabourerStats.FleeRadius, Fleeing = true };
            }

            if (Carrying >= LabourerStats.LoadLimit || (Carrying > 0 && _tookNothing))
                return Deliver(view);

            _retarget -= delta;
            if (Gone(_site, view) || _retarget <= 0f)
            {
                _retarget = LabourerStats.RetargetInterval;
                _site = FindSite(view);
            }
            if (_site == null) return new LabourOrder { Goal = view.Home };

            var spot = _site.At;
            float reach = WorkReach(_site);
            if (_site.Kind == SiteKind.Mine)
            {
                spot = _site.Dock;
                reach = LabourerStats.MineDigReach;
            }
            if (view.At.FlatDistance(spot) > reach) return new LabourOrder { Goal = spot, Site = _site };

            _work -= delta;
            if (_work > 0f) return new LabourOrder { Goal = view.At, Site = _site };
            _work = LabourerStats.WorkInterval * (view.Hungry ? Res.HungerSlowdown : 1f);
            return new LabourOrder { Goal = view.At, Site = _site, Action = ActionFor(_site) };
        }

        /// Источник пропал из мира (повален, разбит, снесён) — искать новый.
        static bool Gone(WorkSite site, LabourerView view)
        {
            return site == null || (site != view.SideMine && !view.Sites.Contains(site));
        }

        LabourAction ActionFor(WorkSite site)
        {
            if (Role == LabourerRole.Builder) return LabourAction.Build;
            switch (site.Kind)
            {
                case SiteKind.Mine: return LabourAction.Dig;
                case SiteKind.Farm: return LabourAction.Take;
                default: return LabourAction.Harvest;
            }
        }

        /// Удар по дереву или камню принёс добычу.
        public void Harvested(ResourceKind kind)
        {
            _tookNothing = false;
            Load[(int)kind] += Res.YieldPerHit;
        }

        /// Источник исчерпан (дерево повалено, камень разбит) — искать другой.
        public void SiteGone() { _site = null; }

        /// С поля взято столько (сколько влезло в ношу).
        public void Took(int[] taken)
        {
            int got = 0;
            for (int i = 0; i < Res.Count; i++)
            {
                int value = Res.At(taken, i);
                Load[i] += value;
                got += value;
            }
            _tookNothing = got <= 0;
        }

        public int Room { get { return LabourerStats.LoadLimit - Carrying; } }

        LabourOrder Deliver(LabourerView view)
        {
            if (!_drop.HasValue) _drop = DropPoint(view);
            if (view.At.FlatDistance(_drop.Value) > WorkReach(_dropSite))
                return new LabourOrder { Goal = _drop.Value };
            return new LabourOrder { Goal = view.At, Action = LabourAction.Deliver };
        }

        /// Сдать ношу: сперва на склад, не влезшее — в казну при себе. Возвращает сданное.
        public int Unload(Wallet wallet)
        {
            int brought = 0;
            for (int i = 0; i < Res.Count; i++)
            {
                int have = Load[i];
                if (have <= 0) continue;
                int left = have - wallet.AddStored(i, have);
                if (left > 0) wallet.Add(i, left);
                brought += have;
            }
            Load = Res.Empty();
            _drop = null;
            _dropSite = null;
            _work = 0f;
            return brought;
        }

        /// При смерти ноша падает на землю.
        public int[] DropOnDeath()
        {
            var dropped = Load;
            Load = Res.Empty();
            return dropped;
        }

        V3 DropPoint(LabourerView view)
        {
            _dropSite = null;
            V3 best = view.Home;
            float bestDistance = float.MaxValue;
            foreach (var site in view.Sites)
            {
                if (site.Kind != SiteKind.Storage || site.Side != Side) continue;
                float d = view.At.Distance(site.At);
                if (d < bestDistance)
                {
                    bestDistance = d;
                    best = site.At;
                    _dropSite = site;
                }
            }
            return best;
        }

        public static float WorkReach(WorkSite site)
        {
            return LabourerStats.WorkRange + (site != null ? site.Body : 0f);
        }

        V3? Threat(LabourerView view)
        {
            foreach (var other in view.Others)
                if (Factions.Hostile((int)Side, other.Side) && view.At.FlatDistance(other.At) <= LabourerStats.FleeRadius)
                    return other.At;
            return null;
        }

        WorkSite FindSite(LabourerView view)
        {
            if (Role == LabourerRole.Builder) return Nearest(view, SiteKind.Construction, true);
            if (Role == LabourerRole.Farmer) return Nearest(view, SiteKind.Farm, true);
            if (Role == LabourerRole.Miner && view.SideMine != null) return view.SideMine;
            var wanted = LabourerStats.Resources(Role);
            WorkSite best = null;
            float bestDistance = float.MaxValue;
            foreach (var site in view.Sites)
            {
                if (site.Kind != SiteKind.Harvestable || Array.IndexOf(wanted, site.Resource) < 0) continue;
                float d = view.At.Distance(site.At);
                if (d < bestDistance)
                {
                    bestDistance = d;
                    best = site;
                }
            }
            return best;
        }

        WorkSite Nearest(LabourerView view, SiteKind kind, bool ownOnly)
        {
            WorkSite best = null;
            float bestDistance = float.MaxValue;
            foreach (var site in view.Sites)
            {
                if (site.Kind != kind || (ownOnly && site.Side != Side)) continue;
                float d = view.At.Distance(site.At);
                if (d < bestDistance)
                {
                    bestDistance = d;
                    best = site;
                }
            }
            return best;
        }
    }
}
