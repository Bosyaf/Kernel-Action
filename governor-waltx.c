// SPDX-License-Identifier: GPL-2.0
/*
 * Walt-X CPU Governor v3.2 (Anti Parachute Fix)
 * Engineered for GKI 6.1 (Hybrid API)
 * Features: Adaptive Sampling, Proactive Thermal, Refined big.LITTLE, Max Hold
 */

#include <linux/cpufreq.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/slab.h>
#include <linux/sched/clock.h>
#include <linux/sched/cpufreq.h>
#include <linux/workqueue.h>

/* Walt-X Heuristic Parameters */
static unsigned int target_load_big = 80;
module_param_named(target_load_big, target_load_big, uint, 0644);
static unsigned int target_load_little = 90;
module_param_named(target_load_little, target_load_little, uint, 0644);
static unsigned int fast_ramp_up_load = 90;
module_param(fast_ramp_up_load, uint, 0644);

struct waltx_cpu_info {
    u64 prev_cpu_idle;
    u64 prev_cpu_wall;
    unsigned int target_freq;
    unsigned int thermal_counter;
    unsigned int next_delay_ms;
    unsigned int max_hold_counter; /* Anti Parachute State */
};

static DEFINE_PER_CPU(struct waltx_cpu_info, waltx_info);

struct waltx_policy_info {
    struct delayed_work work;
    struct cpufreq_policy *policy;
};

/* ========================================================================
 * WALT-X v3.2 CORE LOGIC
 * ======================================================================== */
static void waltx_eval_freq(struct cpufreq_policy *policy)
{
    struct waltx_cpu_info *info = &per_cpu(waltx_info, policy->cpu);
    u64 now, idle_time, delta_wall, delta_idle;
    unsigned int load, freq_target, current_freq = policy->cur;
    unsigned int thermal_max = policy->max;

    now = local_clock();
    idle_time = get_cpu_idle_time(policy->cpu, &delta_wall, 0);

    if (info->prev_cpu_wall == 0) {
        info->prev_cpu_wall = now;
        info->prev_cpu_idle = idle_time;
        info->target_freq = current_freq;
        info->next_delay_ms = 20;
        return;
    }

    delta_wall = now - info->prev_cpu_wall;
    delta_idle = idle_time - info->prev_cpu_idle;
    info->prev_cpu_wall = now;
    info->prev_cpu_idle = idle_time;

    if (delta_wall == 0 || delta_idle > delta_wall)
        load = 0;
    else
        load = div64_u64(100 * (delta_wall - delta_idle), delta_wall);

    /* Refined big.LITTLE Awareness */
    bool is_big = (policy->cpuinfo.max_freq > (policy->cpuinfo.min_freq * 2));
    unsigned int dyn_target_load = is_big ? target_load_big : target_load_little;

    /* Decision Matrix */
    if (load >= fast_ramp_up_load) {
        freq_target = thermal_max;
        if (info->max_hold_counter < 5)
            info->max_hold_counter++; /* Activate max hold */
    } else if (load > dyn_target_load) {
        unsigned int freq_adj = thermal_max * load / 100;
        freq_target = max(freq_adj, current_freq);
    } else {
        /* Max Frequency Hold (Anti-Parachuting) */
        if (info->max_hold_counter > 0) {
            freq_target = current_freq; /* Hold frequency, block decay */
            info->max_hold_counter--;
        } else {
            /* Decay Logic (freq_diff / 20) */
            if (current_freq > policy->min) {
                unsigned int freq_diff = current_freq - policy->min;
                unsigned int decay_step = max(policy->min / 100, freq_diff / 20);
                freq_target = (current_freq > policy->min + decay_step) ? current_freq - decay_step : policy->min;
            } else {
                freq_target = policy->min;
            }
        }
    }

    /* Proactive Thermal */
    if (freq_target >= thermal_max) {
        info->thermal_counter++;
        if (info->thermal_counter > 20) {
            freq_target = (thermal_max * 95) / 100;
        }
    } else {
        if (info->thermal_counter > 0)
            info->thermal_counter--;
    }

    /* Jitter Prevention */
    if (freq_target != info->target_freq) {
        info->target_freq = freq_target;
        __cpufreq_driver_target(policy, freq_target, CPUFREQ_RELATION_L);
    }

    /* Adaptive Sampling */
    if (load >= fast_ramp_up_load || load > dyn_target_load) {
        info->next_delay_ms = 10;
    } else if (current_freq == policy->min) {
        info->next_delay_ms = 20;
    } else {
        info->next_delay_ms = 20;
    }
}

static void waltx_work_handler(struct work_struct *work)
{
    struct waltx_policy_info *wpinfo = container_of(work, struct waltx_policy_info, work.work);
    struct cpufreq_policy *policy = wpinfo->policy;
    struct waltx_cpu_info *info = &per_cpu(waltx_info, policy->cpu);

    waltx_eval_freq(policy);
    schedule_delayed_work_on(policy->cpu, &wpinfo->work, msecs_to_jiffies(info->next_delay_ms));
}

/* ========================================================================
 * GKI 6.1 HYBRID API STRUCT
 * ======================================================================== */
static int waltx_init(struct cpufreq_policy *policy)
{
    struct waltx_policy_info *wpinfo = kzalloc(sizeof(*wpinfo), GFP_KERNEL);
    if (!wpinfo)
        return -ENOMEM;
    wpinfo->policy = policy;
    INIT_DEFERRABLE_WORK(&wpinfo->work, waltx_work_handler);
    policy->governor_data = wpinfo;
    return 0;
}

static void waltx_exit(struct cpufreq_policy *policy)
{
    struct waltx_policy_info *wpinfo = policy->governor_data;
    if (wpinfo) {
        cancel_delayed_work_sync(&wpinfo->work);
        kfree(wpinfo);
        policy->governor_data = NULL;
    }
}

static int waltx_start(struct cpufreq_policy *policy)
{
    unsigned int cpu;
    for_each_cpu(cpu, policy->cpus) {
        struct waltx_cpu_info *info = &per_cpu(waltx_info, cpu);
        info->prev_cpu_idle = get_cpu_idle_time(cpu, &info->prev_cpu_wall, 0);
        info->target_freq = policy->cur;
        info->thermal_counter = 0;
        info->max_hold_counter = 0;
        info->next_delay_ms = 20;
    }
    schedule_delayed_work_on(policy->cpu, &((struct waltx_policy_info *)policy->governor_data)->work, msecs_to_jiffies(20));
    return 0;
}

static void waltx_stop(struct cpufreq_policy *policy)
{
    cancel_delayed_work_sync(&((struct waltx_policy_info *)policy->governor_data)->work);
}

static void waltx_limits(struct cpufreq_policy *policy)
{
    waltx_eval_freq(policy);
}

static struct cpufreq_governor waltx_gov = {
    .name		= "walt-x",
    .owner		= THIS_MODULE,
    .init		= waltx_init,
    .exit		= waltx_exit,
    .start		= waltx_start,
    .stop		= waltx_stop,
    .limits		= waltx_limits,
};

static int __init waltx_module_init(void)
{
    return cpufreq_register_governor(&waltx_gov);
}

static void __exit waltx_module_exit(void)
{
    cpufreq_unregister_governor(&waltx_gov);
}

module_init(waltx_module_init);
module_exit(waltx_module_exit);

MODULE_DESCRIPTION("Walt-X v3.2 - Anti Parachute Max Hold");
MODULE_LICENSE("GPL");
