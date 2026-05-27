return {
    version = "1.0.0",

    achievements = {
        eggs_hatched = {
            id = "eggs_hatched",
            display_name = "Egg Hatchery",
            stat = "eggs_hatched",
            reward_type = "currency",
            tiers = {
                {
                    id = "eggs_1",
                    goal = 1,
                    reward = {
                        type = "currency",
                        currency = "gems",
                        amount = 3,
                    },
                },
                {
                    id = "eggs_10",
                    goal = 10,
                    reward = {
                        type = "currency",
                        currency = "gems",
                        amount = 15,
                    },
                },
                {
                    id = "eggs_50",
                    goal = 50,
                    reward = {
                        type = "currency",
                        currency = "gems",
                        amount = 75,
                    },
                },
            },
        },

        breakables_broken = {
            id = "breakables_broken",
            display_name = "Crystal Crusher",
            stat = "breakables_broken",
            reward_type = "currency",
            tiers = {
                {
                    id = "breakables_10",
                    goal = 10,
                    reward = {
                        type = "currency",
                        currency = "coins",
                        amount = 50,
                    },
                },
                {
                    id = "breakables_100",
                    goal = 100,
                    reward = {
                        type = "currency",
                        currency = "gems",
                        amount = 25,
                    },
                },
            },
        },

        distinct_pets = {
            id = "distinct_pets",
            display_name = "Pet Collector",
            stat = "distinct_pets",
            reward_type = "currency",
            tiers = {
                {
                    id = "distinct_3",
                    goal = 3,
                    reward = {
                        type = "currency",
                        currency = "gems",
                        amount = 10,
                    },
                },
                {
                    id = "distinct_10",
                    goal = 10,
                    reward = {
                        type = "currency",
                        currency = "gems",
                        amount = 60,
                    },
                },
            },
        },
    },
}
