/* zig-nlopt smoke test, C: minimise (x-1)^2 + (y-2)^2 on [-5,5]^2 with a C
   algorithm (Nelder-Mead) and a C++ one inside libnlopt (StoGO, so the
   link needs nlopt.pc's -lc++), prints OK. */
#include <stdio.h>
#include <math.h>
#include <nlopt.h>

static double f(unsigned n, const double *x, double *grad, void *data) {
    (void)n;
    (void)data;
    if (grad) {
        grad[0] = 2.0 * (x[0] - 1.0);
        grad[1] = 2.0 * (x[1] - 2.0);
    }
    return (x[0] - 1.0) * (x[0] - 1.0) + (x[1] - 2.0) * (x[1] - 2.0);
}

static int run(nlopt_algorithm alg) {
    double lb[2] = {-5.0, -5.0}, ub[2] = {5.0, 5.0}, x[2] = {-3.0, 4.0}, minf = 0.0;
    nlopt_opt opt = nlopt_create(alg, 2);
    nlopt_set_lower_bounds(opt, lb);
    nlopt_set_upper_bounds(opt, ub);
    nlopt_set_min_objective(opt, f, NULL);
    nlopt_set_xtol_rel(opt, 1e-8);
    nlopt_set_maxeval(opt, 20000);
    nlopt_result r = nlopt_optimize(opt, x, &minf);
    printf("%s: result %d, x = (%.6f, %.6f), f = %.3g\n", nlopt_algorithm_name(alg), (int)r, x[0], x[1], minf);
    nlopt_destroy(opt);
    return r > 0 && fabs(x[0] - 1.0) < 1e-3 && fabs(x[1] - 2.0) < 1e-3;
}

int main(void) {
    int major, minor, bugfix;
    nlopt_version(&major, &minor, &bugfix);
    printf("nlopt %d.%d.%d\n", major, minor, bugfix);
    if (!run(NLOPT_LN_NELDERMEAD) || !run(NLOPT_GD_STOGO)) {
        puts("FAIL: wrong minimum");
        return 1;
    }
    puts("OK");
    return 0;
}
