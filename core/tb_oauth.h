/* Google OAuth 2.0 device flow with the YouTube TV client ID (research-features §4.4 option A; Opaline, SmartTube,
 * YouTube.js). The token works only with the TVHTML5 InnerTube client. */
#ifndef TB_OAUTH_H
#define TB_OAUTH_H

typedef struct { char *client_id, *client_secret; } tb_oauth_client;
typedef struct { char *user_code, *verification_url, *device_code; int interval, expires_in; } tb_device_code;
typedef struct { char *access_token, *refresh_token; int expires_in; char *error; } tb_token;

/* Read the TV client ID and secret from https://www.youtube.com/tv base.js (about 1.1 MB, once; cache the result). */
int tb_oauth_get_client(tb_oauth_client *out);
/* Pure part of the above, for tests: find clientId:"..." and the secret after it in base.js text. */
int tb_oauth_parse_client(const char *js, tb_oauth_client *out);
int tb_oauth_device_code(const tb_oauth_client *c, const char *device_id, tb_device_code *out);
/* 0 = token in out; 1 = still waiting for the person (authorization_pending / slow_down); < 0 = failed (out->error). */
int tb_oauth_poll(const tb_oauth_client *c, const char *device_code, tb_token *out);
int tb_oauth_refresh(const tb_oauth_client *c, const char *refresh_token, tb_token *out);
void tb_oauth_client_free(tb_oauth_client *c);
void tb_device_code_free(tb_device_code *d);
void tb_token_free(tb_token *t);
#endif
