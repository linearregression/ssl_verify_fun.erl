-module(ssl_verify_pk).
-export([verify_fun/3]).

-ifdef(TEST).
-export([verify_cert_pk/2]).
-endif.

-include_lib("public_key/include/public_key.hrl").

bin_to_hexstr(Bin) ->
  lists:flatten([io_lib:format("~2.16.0B", [X]) ||
                  X <- binary_to_list(Bin)]).


hexstr_to_bin(S) when is_list(S) and (length(S) rem 2 =:= 0) ->
  hexstr_to_bin(S, []);
hexstr_to_bin(_) ->
  invalid.
hexstr_to_bin([], Acc) ->
  list_to_binary(lists:reverse(Acc));
hexstr_to_bin([X,Y|T], Acc) ->
  {ok, [V], []} = io_lib:fread("~16u", [X,Y]),
  hexstr_to_bin(T, [V | Acc]).

%% plain - just plain bytes
pk_info_to_pk(plain, PK) when is_binary(PK) ->
  PK;
pk_info_to_pk(plain, PK) ->
  hexstr_to_bin(PK);
%% base64 - pk encoded using base64 (same as openssl does)
pk_info_to_pk(base64, PK) when is_binary(PK) ->
  base64:decode(PK);
pk_info_to_pk(base64, PK) when is_list(PK) and (length(PK) rem 4 =:= 0)->
  base64:decode(PK);
%% pk is hashed, do not care about exact algorithm here
pk_info_to_pk(_, PKHash) when is_binary(PKHash) ->
  PKHash;
pk_info_to_pk(_, PKHash) ->
  hexstr_to_bin(PKHash).

try_match_encoded_pk(plain, Encoded, Encoded) ->
  {valid, Encoded};
try_match_encoded_pk(plain, _Encoded, PK) ->
  {fail, PK};
try_match_encoded_pk(base64, Encoded, Encoded) ->
  {valid, Encoded};
try_match_encoded_pk(base64, _Encoded, PK) ->
  {fail, PK};
try_match_encoded_pk(HashAlgorithm, Encoded, PK) ->
  Hash = crypto:hash(HashAlgorithm, Encoded),
  case Hash of
    PK ->
      {valid, PK};
    _ ->
      {fail, PK}
  end.

verify_cert_pk(Cert, PK, CheckPKAlgorithm) ->
  TBSCert = Cert#'OTPCertificate'.tbsCertificate,
  PublicKeyInfo = TBSCert#'OTPTBSCertificate'.subjectPublicKeyInfo,
  PublicKey = PublicKeyInfo#'OTPSubjectPublicKeyInfo'.subjectPublicKey,
  %% pem_entry_encode can't encode ec algorithms
  {'SubjectPublicKeyInfo', Encoded, not_encrypted} = public_key:pem_entry_encode('SubjectPublicKeyInfo', PublicKey),

  try_match_encoded_pk(CheckPKAlgorithm, Encoded, PK).

verify_cert_pk(Cert, CheckPK) ->
  {CheckPKAlgorithm, PK} = CheckPK,
  case pk_info_to_pk(CheckPKAlgorithm, PK) of
    invalid -> {fail, invalid_pk};
    PKB -> verify_cert_pk(Cert, PKB, CheckPKAlgorithm)
  end.


verify_fun(_,{bad_cert, _}, UserState) ->
  {valid, UserState};
verify_fun(_,{extension, _}, UserState) ->
  {unknown, UserState};
verify_fun(_, valid, UserState) ->
  {valid, UserState};
verify_fun(Cert, valid_peer, UserState) ->
  CheckPK = proplists:get_value(check_pk, UserState),
  if
    CheckPK /= undefined ->
      verify_cert_pk(Cert, CheckPK);
    true -> {valid, UserState}
  end.
