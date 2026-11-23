/* zig-glpk smoke test: a small LP with the simplex method and the exact
   (GMP rational) simplex, prints OK. Optimum: x=2, y=6, z=36. */
#include <stdio.h>
#include <math.h>
#include <glpk.h>

static int solve(int exact) {
    /* max 3x + 5y  s.t.  x <= 4, 2y <= 12, 3x + 2y <= 18, x, y >= 0 */
    int ia[1 + 4], ja[1 + 4];
    double ar[1 + 4];
    glp_prob *lp = glp_create_prob();
    glp_set_obj_dir(lp, GLP_MAX);
    glp_add_rows(lp, 3);
    glp_set_row_bnds(lp, 1, GLP_UP, 0.0, 4.0);
    glp_set_row_bnds(lp, 2, GLP_UP, 0.0, 12.0);
    glp_set_row_bnds(lp, 3, GLP_UP, 0.0, 18.0);
    glp_add_cols(lp, 2);
    glp_set_col_bnds(lp, 1, GLP_LO, 0.0, 0.0);
    glp_set_col_bnds(lp, 2, GLP_LO, 0.0, 0.0);
    glp_set_obj_coef(lp, 1, 3.0);
    glp_set_obj_coef(lp, 2, 5.0);
    ia[1] = 1, ja[1] = 1, ar[1] = 1.0;
    ia[2] = 2, ja[2] = 2, ar[2] = 2.0;
    ia[3] = 3, ja[3] = 1, ar[3] = 3.0;
    ia[4] = 3, ja[4] = 2, ar[4] = 2.0;
    glp_load_matrix(lp, 4, ia, ja, ar);
    glp_smcp parm;
    glp_init_smcp(&parm);
    parm.msg_lev = GLP_MSG_OFF;
    int rc = exact ? glp_exact(lp, &parm) : glp_simplex(lp, &parm);
    double z = glp_get_obj_val(lp), x = glp_get_col_prim(lp, 1), y = glp_get_col_prim(lp, 2);
    int ok = rc == 0 && glp_get_status(lp) == GLP_OPT && fabs(z - 36.0) < 1e-9 &&
             fabs(x - 2.0) < 1e-9 && fabs(y - 6.0) < 1e-9;
    printf("%s: rc %d, z = %g, x = %g, y = %g\n", exact ? "glp_exact" : "glp_simplex", rc, z, x, y);
    glp_delete_prob(lp);
    return ok;
}

int main(void) {
    glp_term_out(GLP_OFF);
    if (!solve(0) || !solve(1)) {
        puts("FAIL: wrong optimum");
        return 1;
    }
    printf("glpk %s\n", glp_version());
    glp_free_env();
    puts("OK");
    return 0;
}
