/* zig-gsl smoke test: special functions, BLAS through GSL's own CBLAS
   (libgslcblas), numerical integration, an ODE, an RNG draw, and the
   header against the library version; prints OK. */
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <gsl/gsl_blas.h>
#include <gsl/gsl_errno.h>
#include <gsl/gsl_integration.h>
#include <gsl/gsl_odeiv2.h>
#include <gsl/gsl_rng.h>
#include <gsl/gsl_sf_bessel.h>
#include <gsl/gsl_sf_gamma.h>
#include <gsl/gsl_version.h>

static int fail(const char *what, double got, double want) {
    printf("FAIL: %s = %.17g (want %.17g)\n", what, got, want);
    return 1;
}

static double gauss(double x, void *p) { (void)p; return exp(-x * x); }

/* y' = -y, y(0) = 1, so y(1) = 1/e */
static int decay(double t, const double y[], double dydt[], void *p) {
    (void)t; (void)p;
    dydt[0] = -y[0];
    return GSL_SUCCESS;
}

int main(void) {
    /* J0(5) = -0.17759677131433830... (A&S table 9.1) */
    double j0 = gsl_sf_bessel_J0(5.0);
    if (fabs(j0 - (-0.17759677131433830)) > 1e-15) return fail("J0(5)", j0, -0.17759677131433830);
    double g = gsl_sf_gamma(5.5); /* 52.342777784553520... */
    if (fabs(g - 52.34277778455352) > 1e-12) return fail("gamma(5.5)", g, 52.34277778455352);

    /* C = A B with dgemm (libgslcblas) */
    double a[] = {1, 2, 3, 4}, b[] = {5, 6, 7, 8}, c[] = {0, 0, 0, 0};
    gsl_matrix_view A = gsl_matrix_view_array(a, 2, 2), B = gsl_matrix_view_array(b, 2, 2),
                    C = gsl_matrix_view_array(c, 2, 2);
    gsl_blas_dgemm(CblasNoTrans, CblasNoTrans, 1.0, &A.matrix, &B.matrix, 0.0, &C.matrix);
    if (c[0] != 19 || c[1] != 22 || c[2] != 43 || c[3] != 50) {
        printf("FAIL: dgemm = [%g %g; %g %g] (want [19 22; 43 50])\n", c[0], c[1], c[2], c[3]);
        return 1;
    }

    /* integral of exp(-x^2) over (-inf, inf) = sqrt(pi) */
    gsl_integration_workspace *w = gsl_integration_workspace_alloc(1000);
    gsl_function f = {gauss, NULL};
    double r, err;
    gsl_integration_qagi(&f, 0, 1e-12, 1000, w, &r, &err);
    gsl_integration_workspace_free(w);
    if (fabs(r - sqrt(M_PI)) > 1e-10) return fail("integral exp(-x^2)", r, sqrt(M_PI));

    gsl_odeiv2_system sys = {decay, NULL, 1, NULL};
    gsl_odeiv2_driver *d = gsl_odeiv2_driver_alloc_y_new(&sys, gsl_odeiv2_step_rkf45, 1e-6, 1e-12, 0);
    double t = 0, y[1] = {1.0};
    int s = gsl_odeiv2_driver_apply(d, &t, 1.0, y);
    gsl_odeiv2_driver_free(d);
    if (s != GSL_SUCCESS || fabs(y[0] - exp(-1.0)) > 1e-9) return fail("ode y(1)", y[0], exp(-1.0));

    /* mt19937 with the default seed: the first draw is 4293858116 (GSL
       manual, "Random number generator examples") */
    gsl_rng *rng = gsl_rng_alloc(gsl_rng_mt19937);
    unsigned long u = gsl_rng_get(rng);
    gsl_rng_free(rng);
    if (u != 4293858116UL) { printf("FAIL: mt19937 first draw %lu (want 4293858116)\n", u); return 1; }

    if (strcmp(gsl_version, GSL_VERSION) != 0) {
        printf("FAIL: library %s, header %s\n", gsl_version, GSL_VERSION);
        return 1;
    }
    printf("gsl %s: J0(5) = %.15f, sqrt(pi) = %.12f, y(1) = %.10f\n", gsl_version, j0, r, y[0]);
    puts("OK");
    return 0;
}
