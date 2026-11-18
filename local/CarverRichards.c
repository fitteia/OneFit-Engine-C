/*
 * Corrected Carver-Richards two-site CPMG base-library models.
 *
 * Base: Carver & Richards, J. Magn. Reson. 6 (1972), 89-105,
 *       0022-2364(72)90090-x.pdf, p.104, Appendix A1-A10.
 * Replace A3-A5 by Hills, Takacs & Belton, Mol. Phys. 67 (1989),
 *       903-918, 00268978900101531.pdf, p.911, equations (1)-(3).
 *
 * Inputs: tcp, T2A, T2B, tauA, tauB in seconds; omegaA, omegaB in rad/s.
 * tcp is the 180-to-180 pulse separation, NOT the 90-to-180 delay.
 * R2_CR returns 1/T2 in s^-1; T2_CR returns T2 in seconds.
 * tauA and tauB are residence times (A->B and B->A, respectively).
 * Positive infinite residence times represent zero exchange rates.
 * Populations obey PA/tauA = PB/tauB, PA+PB=1 (equilibrium).
 *
 * Registered base-library models for OFE-Raku and OFE-Go.
 * No auxiliary source or AuxDeclar is needed after rebuilding/installing C.
 *
 * This implements the dominant lambda1 rate of A1, not a finite-echo
 * two-component signal or the alternating echo-height ripple.
 * A2 is evaluated with equivalent identities to avoid large cosh/sinh
 * overflow and the loss of a small logarithm near lambda1=1.
 */
#include <math.h>
#include <float.h>
#include "CarverRichards.h"

double R2_CR(double tcp, double T2A, double T2B,
             double tauA, double tauB, double omegaA, double omegaB)
{
    double kA, kB, dw, alpha_minus, alpha_plus, psi, zeta, rho;
    double q, Dplus, Dminus, xi, eta, log_lambda1;

    if (!isfinite(tcp) || tcp <= 0.0 ||
        !isfinite(T2A) || T2A <= 0.0 ||
        !isfinite(T2B) || T2B <= 0.0 ||
        isnan(tauA) || tauA <= 0.0 || isnan(tauB) || tauB <= 0.0 ||
        !isfinite(omegaA) || !isfinite(omegaB))
        return NAN;

    kA = 1.0 / tauA;
    kB = 1.0 / tauB;

    dw = omegaB - omegaA;                              /* A10 */
    alpha_plus  = 1.0/T2A + 1.0/T2B + kA + kB;         /* A9  */
    alpha_minus = 1.0/T2A - 1.0/T2B + kA - kB;         /* A8  */
    zeta = 2.0 * dw * alpha_minus;                     /* A7  */
    psi = alpha_minus*alpha_minus - dw*dw + 4.0*kA*kB; /* A6  */
    rho = hypot(psi, zeta);  /* sqrt(psi^2 + zeta^2) */
    if (!isfinite(rho) || !isfinite(alpha_plus))
        return NAN;

    if (rho == 0.0) {
        /* Continuous limit at psi=zeta=0; A3 itself is 0/0 here. */
        log_lambda1 = -tcp*alpha_plus/2.0 + asinh(tcp*fabs(dw)/2.0);
        return -log_lambda1 / tcp;
    }

    /* A3, replaced by Hills et al. equation (1):
     * 2 D_{+/-} = +/-1 + (psi + 2 dw^2)/rho.
     * The original paper's extra factor 2 in the ratio is REMOVED.
     */
    q = (psi + 2.0*dw*dw) / rho;
    if (!isfinite(q) || q < 1.0 - 64.0*DBL_EPSILON)
        return NAN;
    Dplus  = 0.5 * (q + 1.0);
    Dminus = fmax(0.0, 0.5 * (q - 1.0));

    /* A4 and A5, replaced by Hills et al. equations (2) and (3).
     * Positive roots suffice because A2 contains only their squares.
     * Use |zeta|/sqrt(rho +/- psi) to avoid subtractive cancellation
     * in the smaller root; (rho-psi)(rho+psi)=zeta^2.
     */
    if (psi >= 0.0) {
        double root = sqrt(rho + psi);
        xi  = tcp / (2.0*sqrt(2.0)) * root;
        eta = tcp / (2.0*sqrt(2.0)) * (fabs(zeta) / root);
    } else {
        double root = sqrt(rho - psi);
        xi  = tcp / (2.0*sqrt(2.0)) * (fabs(zeta) / root);
        eta = tcp / (2.0*sqrt(2.0)) * root;
    }

    /* A2:
     * log(lambda1) = -tcp*alpha_plus/2
     *   + log(sqrt(Dplus*cosh(xi)^2 - Dminus*cos(eta)^2)
     *       + sqrt(Dplus*sinh(xi)^2 + Dminus*sin(eta)^2)).
     * With Y = Dplus*sinh(xi)^2 + Dminus*sin(eta)^2,
     * the first radicand equals 1+Y, since Dplus-Dminus=1.
     * Thus the logarithm equals asinh(sqrt(Y)).
     */
    if (xi <= 20.0) {
        double sqrtY = hypot(sqrt(Dplus)*sinh(xi),
                             sqrt(Dminus)*sin(eta));
        log_lambda1 = -tcp*alpha_plus/2.0 + asinh(sqrtY);
    } else {
        /* Exact rescaling of A2 by exp(-xi), not the asymptotic
         * approximation on p.105 of the original paper.
         */
        double e = exp(-2.0*xi);
        double s = -expm1(-2.0*xi); /* 1-exp(-2xi) */
        double se = sin(eta);
        double Yscaled = 0.25*Dplus*s*s + Dminus*e*se*se;
        double logterm = xi + log(sqrt(e + Yscaled) + sqrt(Yscaled));
        log_lambda1 = -tcp*alpha_plus/2.0 + logterm;
    }

    return -log_lambda1 / tcp;                         /* A1 */
}

double T2_CR(double tcp, double T2A, double T2B,
             double tauA, double tauB, double omegaA, double omegaB)
{
    return 1.0 / R2_CR(tcp,T2A,T2B,tauA,tauB,omegaA,omegaB);
}

/* Optional Hills-style parameters: A=free, B=bound.
 * pB is the equilibrium bound fraction; kB=1/tauB in s^-1.
 * Detailed balance gives kA=pB*kB/(1-pB).
 * dw is omegaB-omegaA in rad/s; a common frequency offset cancels.
 */
double R2_CR_pb(double tcp, double T2A, double T2B,
                double pB, double kB, double dw)
{
    double kA;
    if (!isfinite(pB) || pB <= 0.0 || pB >= 1.0 ||
        !isfinite(kB) || kB <= 0.0)
        return NAN;
    kA = pB*kB/(1.0-pB);
    return R2_CR(tcp,T2A,T2B,1.0/kA,1.0/kB,0.0,dw);
}
