# A package's patches as CycloneDX 1.5 `pedigree.patches`, for nix/sbom.nix.
#
#   of pkg purl -> [ { type; diff = { url; text?; }; resolves?; } ]
#
# `pkg.patches` is the list the package applies; `purl` the [upstream] purl of its source (null
# when it has none), for commit links. Each patch file is read at evaluation:
#   - type: "backport" when the patch says it is an upstream commit, else "unofficial" (a change
#     of this tree's own, submitted upstream or not). The markers, in its message:
#       (cherry picked from commit <sha>)          what `git cherry-pick -x` writes
#       Origin: upstream|backport[, <url>|commit:<sha>]     DEP-3
#       Applied-Upstream: <url>|commit:<sha>               DEP-3
#     A bare `Origin: upstream` takes the commit from `git format-patch`'s `From <sha>` line. That
#     line alone says only which commit the file was made from, often a commit of this tree's
#     own, so it makes no backport.
#   - diff.url: for a backport the upstream commit (the marker's URL, or a commit on the purl's
#     github or gitlab project); otherwise, or with no way to link, the file relative to the
#     package's directory. diff.text: the whole file, so the SBOM alone shows what changed.
#   - resolves: one issue from the patch's own header: `name` is the `Subject:` of `git
#     format-patch` ([PATCH …] dropped) or a DEP-3 `Description:`, else the first paragraph
#     before the diff; `references` the other URLs in that message; `type` "defect" for a
#     subject whose summary starts with "fix", else "enhancement". A bare diff resolves nothing.
# A patch that is a derivation (fetched) is not read at evaluation: its name only, unofficial.
let
  inherit (builtins)
    baseNameOf
    concatStringsSep
    elemAt
    filter
    head
    isList
    isPath
    isString
    match
    readFile
    split
    stringLength
    substring
    tail
    toString
    ;

  lines = s: filter isString (split "\n" s);
  firstMatch =
    re: ls:
    let
      hits = filter (m: m != null) (map (match re) ls);
    in
    if hits == [ ] then null else head hits;

  # the lines from the start up to (not including) the first line `stop` matches
  takeUntil =
    stop: ls: if ls == [ ] || stop (head ls) then [ ] else [ (head ls) ] ++ takeUntil stop (tail ls);
  dropUntil = stop: ls: if ls == [ ] || stop (head ls) then ls else dropUntil stop (tail ls);

  # the commit message: the text before the diff, and before format-patch's "---" and diffstat
  messageOf =
    content:
    takeUntil (l: l == "---" || match "(diff |--- |\\+\\+\\+ |Index: |@@ ).*" l != null) (
      lines content
    );

  # Subject: (or DEP-3 Description:) with its folded lines (a continuation starts with a blank)
  subjectOf =
    msg:
    let
      from = dropUntil (l: match "(Subject|Description): .*" l != null) msg;
      folded = takeUntil (l: match "[ \t].*" l == null) (tail from);
      raw = concatStringsSep " " (
        [ (head (match "[A-Za-z]+: (.*)" (head from))) ] ++ map (l: head (match "[ \t]+(.*)" l)) folded
      );
      stripped = match "\\[PATCH[ A-Za-z0-9/.-]*] *(.*)" raw;
    in
    if from == [ ] then
      null
    else if stripped == null then
      raw
    else
      head stripped;

  # the first paragraph of free text
  paragraphOf =
    msg:
    let
      p = takeUntil (l: l == "") (dropUntil (l: l != "") msg);
    in
    if p == [ ] then null else concatStringsSep " " p;

  urlRe = "(https?://[^[:space:]<>\"]*[^[:space:]<>\".,;:)])";
  urlsOf = msg: map head (filter isList (split urlRe (concatStringsSep "\n" msg)));

  markerRe = "(Origin|Applied-Upstream): .*";
  issueOf =
    msg:
    let
      subject = subjectOf msg;
      name = if subject != null then subject else paragraphOf msg;
      # the backport markers' URLs name the commit, not an issue
      urls = urlsOf (filter (l: match markerRe l == null) msg);
    in
    if name == null then
      [ ]
    else
      [
        (
          {
            type = if match "([^:]+: )?[Ff]ix.*" name != null then "defect" else "enhancement";
            inherit name;
          }
          // (if urls == [ ] then { } else { references = urls; })
        )
      ];

  # the upstream commit a patch says it is: { url } or { sha }, { } for an unnamed one, or null
  # when it says nothing
  upstreamOf =
    msg:
    let
      ref =
        v:
        if v == null || v == "" then
          { }
        else if match "commit:([0-9a-f]{7,40})" v != null then
          { sha = head (match "commit:([0-9a-f]{7,40})" v); }
        else if match urlRe v != null then
          { url = v; }
        else
          { };
      picked = firstMatch ".*\\(cherry picked from commit ([0-9a-f]{7,40})\\).*" msg;
      origin = firstMatch "Origin: *(upstream|backport)(, *([^ ]*))? *" msg;
      applied = firstMatch "Applied-Upstream: *([^ ]*) *" msg;
      header = firstMatch "From ([0-9a-f]{40}) Mon Sep 17 00:00:00 2001" msg;
    in
    if picked != null then
      { sha = head picked; }
    else if origin != null then
      let
        r = ref (elemAt origin 2);
      in
      if r == { } && header != null then { sha = head header; } else r
    else if applied != null then
      ref (head applied)
    else
      null;

  # a commit on the purl's project: github, gitlab (repository_url for another host)
  commitUrl =
    purl: sha:
    let
      m = if purl == null then null else match "pkg:(github|gitlab)/([^?#@]+)(\\?(.*))?" purl;
      host =
        let
          q = match "(.*&)?repository_url=([^&]+).*" (if elemAt m 3 == null then "" else elemAt m 3);
        in
        if elemAt m 0 == "github" then
          "https://github.com"
        else if q != null then
          elemAt q 1
        else
          "https://gitlab.com";
    in
    if m == null then
      null
    else if elemAt m 0 == "github" then
      "${host}/${elemAt m 1}/commit/${sha}"
    else
      "${host}/${elemAt m 1}/-/commit/${sha}";

  relativeTo =
    pkg: file:
    let
      dir = toString (pkg.dir or "") + "/";
      f = toString file;
      n = stringLength dir;
    in
    if pkg ? dir && substring 0 n f == dir then substring n (stringLength f) f else baseNameOf f;

  patchOf =
    pkg: purl: file:
    if isPath file then
      let
        content = readFile file;
        msg = messageOf content;
        upstream = upstreamOf msg;
        url =
          if upstream == null then
            null
          else
            upstream.url or (if upstream ? sha then commitUrl purl upstream.sha else null);
        resolves = issueOf msg;
      in
      {
        type = if upstream == null then "unofficial" else "backport";
        diff = {
          url = if url == null then relativeTo pkg file else url;
          text = {
            contentType = "text/x-diff";
            inherit content;
          };
        };
      }
      // (if resolves == [ ] then { } else { inherit resolves; })
    else
      let
        n = file.name or (baseNameOf (builtins.unsafeDiscardStringContext (toString file)));
        bare = match "[0-9a-z]{32}-(.*)" n;
      in
      {
        type = "unofficial";
        diff.url = if bare == null then n else head bare;
      };
in
{
  of = pkg: purl: map (patchOf pkg purl) (if isList (pkg.patches or null) then pkg.patches else [ ]);
}
