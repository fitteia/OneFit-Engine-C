/* Corrected Carver-Richards CPMG model; see CarverRichards.c for sources.
 * tcp: 180-to-180 separation (s); T2 and residence times: s; omega,dw: rad/s.
 */
#ifndef OFE_CARVER_RICHARDS_H
#define OFE_CARVER_RICHARDS_H

double R2_CR(double tcp, double T2A, double T2B, double tauA, double tauB, double omegaA, double omegaB);
double T2_CR(double tcp, double T2A, double T2B, double tauA, double tauB, double omegaA, double omegaB);
double R2_CR_pb(double tcp, double T2A, double T2B, double pB, double kB, double dw);

#endif
