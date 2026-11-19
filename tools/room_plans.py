"""Route skeletons for tools/solve_rooms.py: one function per room returning its stages (cells are grid (col, row)).

Derived from design/rooms/<id>.yaml `intended_solution`. They say WHERE to go and WHAT to do; tools/solve_rooms.py searches
WHEN (waiting at safe cells) against the recorded guard patrols, and the recorder checks the result on the real ROM.
"""
from solve_rooms import Act, Move


def slot(room, gid):
    """Sprite slot of guard `gid` (roomgen writes the sprite list in row-major order of the grid)."""
    for i, g in enumerate(room.guards):
        if g["id"] == gid:
            return i
    raise KeyError(gid)


def face(d):
    return Act("face", d)


def item(name):
    return Act("item", name)


def shoot(room, gid):
    return Act("shoot", slot(room, gid))


def pot(d):
    return Act("pot", d)


def stab(room, gid, d, dist=30, maxwait=400):
    return Act("stab", slot(room, gid), d, dist, maxwait)


def r01(room):
    return [Move((13, 8), (10, 8), (10, 6), (1, 6), (1, 3), order=["yx", "xy", "yx", "xy", "yx"])]


def r02(room):
    return [Move((7, 11)), Move((7, 3), order=["yx"]), Move((13, 3), (13, 2), order=["xy", "yx"])]


def r03(room):
    return [Move((5, 4, -4, 0)), stab(room, "a", "right"), Move((12, 4), (12, 11), order=["xy", "yx"])]


def r04(room):
    return [Move((4, 9), order=["yx"]), Move((4, 7), (14, 7), order=["yx", "xy"])]


def r05(room):
    return [Move((1, 9), (7, 9), (9, 9), (9, 12), order=["yx", "xy", "xy", "yx"], unchecked=True)]


def r06(room):
    return [
        Move((4, 10), order=["yx"]),
        Move((4, 12), (2, 12, 4, 0), order=["yx", "xy"]),
        stab(room, "c", "left", 30, 200),
        Move((14, 12), (14, 7), order=["xy", "yx"]),
        Move((8, 7, 4, 0), order=["xy"]),
        stab(room, "b", "left", 30, 200),
        Move((1, 7), (1, 5), order=["xy", "yx"]),
        Move((14, 5), order=["xy"]),
    ]


def r07(room):
    return [item("bow"), shoot(room, "a"), Move((1, 6, 0, 4)), stab(room, "a", "up", 30, 100),
            Move((1, 3), (14, 3), order=["yx", "xy"])]


def r08(room):
    return [item("bow"), Move((6, 11), order=["xy"]), Move((6, 7), order=["yx"]), face("right"), shoot(room, "a"),
            Move((9, 7), (9, 12), (14, 12), order=["xy", "yx", "xy"])]


def r09(room):
    return [Move((8, 12), (8, 8), order=["xy", "yx"]), Move((8, 6), (14, 6), order=["yx", "xy"])]


def r10(room):
    return [item("bombs"), face("right"), pot("right"), stab(room, "a", "right", 30, 600), Move((14, 9))]


def r11(room):
    return [Move((7, 11), (7, 6), order=["xy", "yx"]), item("bombs"), face("up"), pot("up"),
            Move((7, 3), order=["yx"]), Move((13, 3), (13, 2), order=["xy", "yx"])]


def r12(room):
    return [item("bow"), Move((3, 4)), face("right"), shoot(room, "a"),
            Move((3, 7)), face("right"), shoot(room, "b"),
            Move((3, 10)), face("right"), shoot(room, "c"),
            Move((10, 10), (10, 12), (14, 12), order=["xy", "yx", "xy"])]


def r13(room):
    return [Move((3, 12)), Move((3, 5), order=["yx"]), Move((3, 3), order=["yx"]), Move((10, 3), order=["xy"]),
            Move((14, 3), (14, 2), order=["xy", "yx"])]


def r14(room):
    return [item("bow"), face("right"), shoot(room, "a"), Move((7, 9), order=["xy"]), Move((7, 5), order=["yx"]),
            item("bombs"), face("up"), pot("up"), Move((7, 2), order=["yx"])]


def r15(room):
    return [Move((1, 6), order=["yx"]), item("bow"), face("right"), shoot(room, "c"), Move((5, 6), order=["xy"]),
            Move((6, 6), (6, 2), order=["xy", "yx"])]


def r16(room):
    return [item("bow"), face("right"), shoot(room, "c"), Move((1, 11), (7, 11), order=["yx", "xy"]), face("up"),
            shoot(room, "a"), Move((7, 7), (13, 7), (13, 2), order=["yx", "xy", "yx"])]


def r17(room):
    return [item("bow"), Move((3, 6), order=["yx"]), Move((3, 5), order=["yx"]), face("right"), shoot(room, "c"),
            Move((3, 6), (10, 6), order=["yx", "xy"]), Move((14, 6), (14, 4), order=["xy", "yx"]),
            item("bombs"), face("up"), pot("up"), Move((14, 3), order=["yx"]), face("left"),
            stab(room, "b", "left", 30, 600), Move((1, 3), order=["xy"])]


def r18(room):
    return [Move((3, 10), order=["xy"]), item("bow"), face("right"), shoot(room, "b"), Move((8, 10), order=["xy"]),
            Move((10, 10), (10, 8), (14, 8), order=["xy", "yx", "xy"])]


def r19(room):
    return [Move((12, 6), order=["xy"]), Move((12, 5), (7, 5, 4, 0), order=["yx", "xy"]), stab(room, "c", "left", 30, 200),
            Move((1, 5), order=["xy"]), Move((1, 4), order=["yx"]), item("bombs"), face("up"), pot("up"),
            Move((1, 3), order=["yx"]), face("right"), stab(room, "b", "right", 30, 600), Move((14, 3), order=["xy"])]


def r20(room):
    return [item("bow"), Move((1, 10), order=["yx"]), face("right"), shoot(room, "a"),
            Move((1, 12), order=["yx"]), face("right"), shoot(room, "b"),
            Move((1, 11), (8, 11), order=["yx", "xy"]), Move((8, 6), order=["yx"]), Move((8, 5), order=["yx"]),
            item("bombs"), face("up"), pot("up"), Move((8, 2), order=["yx"])]


def final(room):
    return [item("bow"), face("left"), shoot(room, "a"), Move((4, 11), (4, 12), order=["xy", "yx"]),
            Move((4, 6), order=["yx"]), face("right"), shoot(room, "c"), Move((8, 6), (8, 5), order=["xy", "yx"]),
            item("bombs"), face("up"), pot("up"), Move((8, 2), order=["yx"])]


PLANS = {k: v for k, v in dict(globals()).items() if k == "final" or (k[0] == "r" and k[1:].isdigit())}
