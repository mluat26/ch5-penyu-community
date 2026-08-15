#!/usr/bin/env bash
# Collect a bounded second-pass pool of public-web images for local prototype
# research. This intentionally downloads only the listed direct image-search
# results: it never crawls a site, authenticates, or reuses source images in a
# distributable artifact. Every record remains unreviewed until a human labels
# it for the detector dataset.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="$repo_root/training/raw/prototype-web-v2"
provenance_dir="$repo_root/training/provenance"
existing_manifest="$provenance_dir/prototype-web-images.json"
json_manifest="$provenance_dir/prototype-web-v2-images.json"
csv_manifest="$provenance_dir/prototype-web-v2-images.csv"
user_agent="community-challenge-prototype-research/1.0 (local testing; contact repository maintainer)"

mkdir -p "$output_dir" "$provenance_dir"

results_file="$(mktemp "${TMPDIR:-/tmp}/prototype-web-v2-results.XXXXXX")"
existing_urls_file="$(mktemp "${TMPDIR:-/tmp}/prototype-web-existing-urls.XXXXXX")"
seen_urls_file="$(mktemp "${TMPDIR:-/tmp}/prototype-web-v2-seen-urls.XXXXXX")"
trap 'rm -f "$results_file" "$existing_urls_file" "$seen_urls_file"' EXIT

printf 'id\tquery\trough_role\tregion\tsource_page_url\timage_url\tdownload_status\tlocal_filename\thttp_code\tmime_type\n' > "$results_file"

if [[ -f "$existing_manifest" ]]; then
  jq -r '.images[]?.image_url // empty' "$existing_manifest" > "$existing_urls_file"
fi

records() {
  cat <<'EOF'
001	sea turtle hatchery sand enclosure Indonesia	hatchery_sand_bed_candidate	Indonesia	https://www.antaranews.com/berita/489415/dkp-bantul-selamatkan-4697-telur-penyu-dari-kawasan-pantai	https://cdn.antaranews.com/cache/1200x800/2014/05/20140502Penangkaran-Telur-Penyu-010514-Fiq-1.jpg
002	sea turtle hatchery sand enclosure India	hatchery_sand_bed_candidate	India	https://www.indiatoday.in/cities/chennai/story/chennai-forest-officials-put-efforts-to-assure-survival-of-olive-ridley-turtles-during-hatching-1931401-2022-03-30	https://akm-img-a-in.tosshub.com/indiatoday/images/story/202203/WhatsApp_Image_2022-03-30_at_1_1_1200x768.jpeg?size=690%3A388
003	sea turtle hatchery sand enclosure India	partial_hatchery_context_candidate	India	https://science.thewire.in/environment/honnavar-port-olive-ridley-turtles/	https://cdn.thewire.in/wp-content/uploads/2022/07/21155821/Olive-Ridley-Turtles-Honnavar-1200x800-1.jpg
004	sea turtle hatchery sand enclosure Mexico	partial_hatchery_context_candidate	Mexico	https://www.naturallybychloe.com/blog/baby-turtle-release-puerto-escondido-mexico	https://images.squarespace-cdn.com/content/v1/608b985238815e50eb27659a/1625851458811-HL7GS0GQEBF3CAM4FV22/699ab73c-552c-47d2-9c7a-602a36557d49.JPG
005	sea turtle hatchery sand enclosure Mexico	hatchery_sand_bed_candidate	Mexico	https://tribunademexico.com/amplian-corral-tortugas/	https://storage.googleapis.com/tribunamexico/2023/09/En-Los-Cabos-amplian-corral-de-anidacion-de-tortugas-905x613.jpeg
006	sea turtle hatchery sand enclosure Malaysia	hatchery_sand_bed_candidate	Malaysia	https://asiadivingvacation.com/resort/pom-pom-island-resort	https://cdn.asiadivingvacation.com/Images/diveresorts/pom-pom-island-resort/turtle-hatchery.webp
007	sea turtle hatchery sand enclosure Malaysia	hatchery_sand_bed_candidate	Malaysia	https://suara.tv/22/06/2020/penyu-karah-khazanah-laut-melaka/	https://assets.bharian.com.my/images/articles/penyu3_1592711150.jpg
008	sea turtle hatchery sand enclosure Malaysia	hatchery_sand_bed_candidate	Malaysia	https://www.tengahislandconservation.org/adopt-a-nest	https://images.squarespace-cdn.com/content/v1/5cdb75971b06b500015927b6/86e8a98a-c817-4404-9db9-c2dbbf468034/_DSC4674.jpg
009	sea turtle hatchery sand enclosure Cabo Verde	hatchery_sand_bed_candidate	Cabo Verde	https://fr.linkedin.com/posts/hortensio-lima-079a5b37_visite-de-terrain-de-la-coordenation-r%C3%A9gional-activity-7207144553760407552-1_M8	https://media.licdn.com/dms/image/v2/D4D22AQE91wCrq6KMpQ/feedshare-shrink_800/feedshare-shrink_800/0/1718317159989?e=2147483647&t=yIey9fPGe9SVgPtdta64ivsQQmzIAvUROS003EHo6bM&v=beta
010	sea turtle hatchery sand enclosure Brazil	partial_hatchery_context_candidate	Brazil	https://vamosviajarpraondeagora.com.br/como-e-o-projeto-tamar-da-praia-do-forte/	https://vamosviajarpraondeagora.com.br/wp-content/uploads/2021/01/IMG_3007-scaled.jpg
011	sea turtle hatchery sand enclosure Brazil	partial_hatchery_context_candidate	Brazil	https://www.guiaviagensbrasil.com/galerias/ba/fotos-do-projeto-tamar/foto-projeto-tamar-na%20praia-do-forte-bahia-brasil-1965/	https://www.guiaviagensbrasil.com/imagens/foto-projeto-tamar-na%20praia-do-forte-bahia-brasil-1965.jpg
012	sea turtle hatchery sand enclosure Sri Lanka	hatchery_sand_bed_candidate	Sri Lanka	https://www.travelkalutara.com/attractions/wildlife/how-to-volunteer-at-kosgoda-turtle-hatchery.html	https://www.travelkalutara.com/wp-content/uploads/2017/12/turtle-hatchery-kosgoda.jpg
013	sea turtle hatchery sand enclosure Sri Lanka	hatchery_sand_bed_candidate	Sri Lanka	https://themightaswellers.com/2015/05/27/a-visit-to-a-sri-lankan-turtle-conservation-project/	https://themightaswellers.com/wp-content/uploads/2015/05/img_5092.jpg
014	sea turtle hatchery sand enclosure Nicaragua	hatchery_sand_bed_candidate	Nicaragua	https://www.el19digital.com/articulos/ver/164281-complejo-turistico-y-habitacional-en-villa-el-carmen-managua-aporta-al-cuido-del-medioambiente	https://www.el19digital.com/files/notas/source/2025/MAYO/19-Mayo/MARENA/MARENA-8.jpg
015	sea turtle hatchery sand enclosure Mexico	hatchery_sand_bed_candidate	Mexico	https://oem.com.mx/elsoldetampico/turismo/el-regreso-de-las-tortugas-lora-a-tamaulipas-playa-miramar-recibe-a-dos-nuevas-visitantes-22956270	https://oem.com.mx/elsoldetampico/img/22899502/1745245948/BASE_LANDSCAPE/1200/image.webp
016	sea turtle hatchery sand enclosure Mexico	hatchery_sand_bed_candidate	Mexico	https://grupomarmor.com.mx/2026/01/25/se-testigo-del-primer-latido-del-mar-vive-la-liberacion-de-tortugas-en-las-costas-michoacanas/	https://grupomarmor.com.mx/storage/2026/01/Tortugas-2.gif
017	sea turtle hatchery sand enclosure Mexico	hatchery_sand_bed_candidate	Mexico	https://www.milenio.com/ciencia-y-salud/medioambiente/interponen-denuncia-campo-tortuguero-playa-miramar	https://cdn.milenio.com/uploads/media/2022/08/25/campo-tortuguero-playa-miramar-anahy.jpg
018	sea turtle hatchery sand enclosure Mexico	hatchery_sand_bed_candidate	Mexico	https://oem.com.mx/diariodexalapa/local/50-universitarios-de-ocho-paises-limpian-playas-y-protegen-tortugas-en-nautla-veracruz-28362973	https://oem.com.mx/diariodexalapa/img/28570232/1771628274/BASE_LANDSCAPE/1200/image.jpg
019	sea turtle hatchery sand enclosure Mexico	hatchery_sand_bed_candidate	Mexico	https://oem.com.mx/diariodexalapa/local/ambientalista-denuncia-sobreexplotacion-de-cangrejos-jaibas-y-tortugas-en-playas-de-vega-de-alatorre-25846672	https://oem.com.mx/diariodexalapa/img/25846478/1758317157/BASE_LANDSCAPE/1200/image.webp
020	sea turtle hatchery sand enclosure Mexico	hatchery_sand_bed_candidate	Mexico	https://hablabiendeaca.com/directorio/aventura-tours/campamento-tortuguero-playa-larga	https://hablabiendeaca.com/images/archivos/201402082019612bb1.jpg
021	sea turtle hatchery sand enclosure Mexico	hatchery_sand_bed_candidate	Mexico	https://www.playaviva.com/perfect-timing	https://lirp.cdn-website.com/fc746e6b/dms3rep/multi/opt/nick-wolf-turtle-markers-640w.jpg
022	sea turtle hatchery sand enclosure Panama	hatchery_sand_bed_candidate	Panama	https://unachi.ac.pa/noticia/2076/capacitacion-sobre-conservacion-de-tortugas-marinas-en-la-universidad-autonoma-de-chiriqui	https://unachi.ac.pa/assets/galerias/galeria_2457/ae2699c7-8947-45cc-8d72-02d5f3a808fb.jpeg
023	sea turtle hatchery sand enclosure Spain	hatchery_sand_bed_candidate	Spain	https://valenciaplaza.com/valenciaplaza/valencia/mas-de-200-voluntarios-vigilaran-los-243-huevos-de-tortuga-marina-llevados-a-una-playa-de-el-saler-hasta-su-eclosion	https://d31u1w5651ly23.cloudfront.net/articulos/articulos-1655056.jpg
024	sea turtle hatchery sand enclosure Mexico	hatchery_sand_bed_candidate	Mexico	https://www.meganoticias.mx/tuxpan/noticia/urgen-recursos-para-campamento-tortuguero/142673	https://www.meganoticias.mx/uploads/noticias/urgen-recursos-para-campamento-tortuguero-142673.jpeg
025	sea turtle hatchery sand enclosure Spain	hatchery_sand_bed_candidate	Spain	https://serbal-almeria.org/noticias/347-la-tortuga-boba-caretta-caretta-nidifica-en-almeria	https://serbal-almeria.org/images/noticias/20210903-nido-tortuga-marina-boba-almeria/Nido-tortuga-boba-2.jpg
026	sea turtle hatchery sand enclosure Malaysia	hatchery_sand_bed_candidate	Malaysia	https://happygokl.com/bubbles-dive-resort/	https://files.happygokl.com/wp-content/uploads/2020/07/bubbles-turtles.jpg
027	sea turtle hatchery sand enclosure Malaysia	hatchery_sand_bed_candidate	Malaysia	https://onpenang.com/penang-turtle-conservation-centre/	https://onpenang.com/wp-content/uploads/2024/04/Penang-Turtle-Sanctuary-5-1024x731.jpg.webp
028	sea turtle hatchery sand enclosure Malaysia	hatchery_sand_bed_candidate	Malaysia	https://pompomisland.com/2013/01/turtle-hatchery-maintenance/	https://www.pompomisland.com/wp-content/uploads/2013/02/Rebuilding-the-hatchery-3.jpg
029	sea turtle hatchery sand enclosure Mexico	hatchery_sand_bed_candidate	Mexico	https://memanta.org/about/reasons-why/	https://memanta.org/wp-content/uploads/2024/05/hatchery-memanta.jpg
030	sea turtle hatchery sand enclosure El Salvador	hatchery_sand_bed_candidate	El Salvador	https://www.laprensagrafica.com/elsalvador/Inauguran-vivero-para-tortugas-marinas-en-Conchagua-20171116-0081.html	https://assets.laprensagrafica.com/__export/1510871010652/sites/prensagrafica/img/2017/11/16/176adc18-2b30-41eb-8de7-386dc2139cc7.jpg_554688468.jpg
031	sea turtle hatchery sand enclosure Nicaragua	hatchery_sand_bed_candidate	Nicaragua	https://www.adventure-life.com/nicaragua/padre-ramos/hotels/padre-ramos	https://cdn.adventure-life.com/53/42/1/dz32stra/663x400.webp
032	sea turtle hatchery sand enclosure Nicaragua	partial_hatchery_context_candidate	Nicaragua	https://www.surfingturtlelodge.com/turtle-hatchery/	https://www.surfingturtlelodge.com/wp-content/uploads/2022/11/seaturtlehatchery800-08.jpg
033	sea turtle hatchery sand enclosure Ghana	hatchery_sand_bed_candidate	Ghana	https://www.apmterminals.com/en/news/news-releases/2020/201015-mps-launches-sea-turtle-conservation-program	https://cms-cd.apmterminals.com/-/media/mainsite/global/news/2020-news/201015-mps-launches-sea-turtle-conservation-program-02.jpg?hash=CE394B4CF5FB650D4F8F653BA55ADA5E&rev=d45f806f49e8492bb4c04b87f7cfd2b9
034	sea turtle hatchery sand enclosure Mexico	partial_hatchery_context_candidate	Mexico	https://holanews.com/liberan-cientos-de-crias-de-tortuga-marina-en-costas-del-pacifico-mexicano/	https://i0.wp.com/holanews.com/wp-content/uploads/2022/11/rss-efe0e35063501486b2328056db5ba1f0dd97abbaad5w.jpg?fit=1920%2C1171&ssl=1
035	sea turtle hatchery sand enclosure India	partial_hatchery_context_candidate	India	https://www.indiatoday.in/india/tamil-nadu/story/olive-ridley-hatchlings-baby-sea-turtles-released-chennai-sea-after-30-day-conservation-2715996-2025-04-28	https://akm-img-a-in.tosshub.com/indiatoday/images/story/202504/olive-ridley-hatchlings-baby-sea-turtles-270403729-16x9_0.jpeg?VersionId=KZ7Z3WtgI3gISIvfHW2l4fQctj5LA7e3
036	sea turtle hatchery sand enclosure El Salvador	partial_hatchery_context_candidate	El Salvador	https://spanish.news.cn/20221017/d25473e0400041e789f8e2bb20ef280c/c.html	https://spanish.news.cn/20221017/d25473e0400041e789f8e2bb20ef280c/20221017d25473e0400041e789f8e2bb20ef280c_2c059356-320d-428b-a33e-fe5499e25314.jpg
037	sea turtle hatchery sand enclosure Qatar	partial_hatchery_context_candidate	Qatar	https://www.timeoutdoha.com/things-to-do/watch-turtles-hatch-at-fuwairit-beach-with-culture-pass	https://www.timeoutdoha.com/cloud/timeoutdoha/2022/06/02/Turtle-hatching1.jpg
038	sea turtle hatchery sand enclosure Mexico	hatchery_sand_bed_candidate	Mexico	https://www.reforma.com/aplicaciones/articulo/default.aspx?id=1415012	https://img.gruporeforma.com/imagenes/960x640/5/85/4084482.jpg
039	sea turtle hatchery sand enclosure Cabo Verde	hatchery_sand_bed_candidate	Cabo Verde	https://www.boavistaofficial.com/explore/natural-reserve-turtle/	https://www.boavistaofficial.com/boa-vista-cabo-verde/wp-content/uploads/2021/04/turtle-nest-reserve-boavista.jpg
040	sea turtle hatchery sand enclosure Cabo Verde	hatchery_sand_bed_candidate	Cabo Verde	https://www.gooverseas.com/volunteer-abroad/cape-verde/program/267663	https://www.gooverseas.com/sites/default/files/styles/1014x/public/image-collections/2021-03-10/hatch5.jpg?itok=HwQbXqRd
041	sea turtle hatchery sand enclosure Cabo Verde	hatchery_sand_bed_candidate	Cabo Verde	https://macaonews.org/news/lusofonia/cabo-cape-verde-turtles-nesting-pollution-cleanup-beaches/	https://macaonews.org/wp-content/uploads/2025/05/shutterstock_2235940159.jpg
042	sea turtle hatchery sand enclosure Malaysia	hatchery_sand_bed_candidate	Malaysia	https://www.tioman.org/juara-turtle-project.htm	https://www.tioman.org/img/juara-turtle-project-nest.jpg
043	sea turtle hatchery sand enclosure Malaysia	hatchery_sand_bed_candidate	Malaysia	https://www.gretchencoffman.org/turtle-conservation-by-tracc-on-pom-pom-island/	https://www.gretchencoffman.org/wp-content/uploads/2016/07/turtle-hatchery.jpg
044	sea turtle hatchery sand enclosure Malaysia	hatchery_sand_bed_candidate	Malaysia	https://www.internhq.com/destinations/malaysia/sea-turtle-conservation-internships-in-malaysia/	https://iahq.imgix.net/images/destinations/malaysia/gallery/malaysia-sea-turtle-conservation-internship-hatchery.jpg?auto=format%2Ccompress&crop=faces%2Ccenter&fit=crop&h=450&q=40&w=800
045	sea turtle hatchery sand enclosure Mexico	hatchery_sand_bed_candidate	Mexico	https://1000caguamas.com/campamento-sayulita/	https://1000caguamas.com/campamento-sayulita/img/08%20Corral%20de%20incubacio%CC%81n%2C%202021.JPG
046	sea turtle hatchery sand enclosure Malaysia	hatchery_sand_bed_candidate	Malaysia	https://www.seeturtles.org/turtle-blog/march-update-2022	https://images.squarespace-cdn.com/content/v1/5369465be4b0507a1fd05af0/07076576-cc63-43ba-87dc-5745696f7e19/Nest%2Bin%2BTegaipil%2Bisland_%2Bcredit%2BReef%2BGuardian.jpg?format=1000w
047	sea turtle hatchery sand enclosure Philippines	partial_hatchery_context_candidate	Philippines	https://awesome.blog/2016/12/pawikan-festival-help-save-the-turtles.html	https://i0.wp.com/c3.staticflickr.com/6/5699/31163551722_51338ee107_b.jpg?quality=89&resize=1024%2C683&ssl=1
048	sea turtle hatchery sand enclosure Philippines	hatchery_sand_bed_candidate	Philippines	https://www.ikelite.com/blogs/features/arribada-pawikan-saving-the-sea-turtles-of-the-philippines	https://cdn.shopify.com/s/files/1/0866/6704/files/wessam-atif-baby-turtle-eggs_1024x1024.jpg?v=1741287083
049	sea turtle hatchery sand enclosure Sao Tome	hatchery_sand_bed_candidate	Sao Tome and Principe	https://www.rainbowtours.co.uk/sao-tome-principe/experiences/southern-beaches-of-sao-tome	https://rainbowtours.imgix.net/1867/turtle-hatchery-praia-inhame-ecolodge-2023-sao-tome.jpg?auto=enhance&crop=focalpoint&fit=crop&fp-x=0.5&fp-y=0.5&fp-z=1&h=490&w=726
050	sea turtle hatchery sand enclosure Indonesia	partial_hatchery_context_candidate	Indonesia	https://news.detik.com/foto-news/d-8144882/potret-relawan-selamatkan-ratusan-telur-penyu-dari-predator-di-tulungagung	https://awsimages.detik.net.id/community/media/visual/2025/10/04/potret-relawan-selamatkan-ratusan-telur-penyu-dari-predator-di-tulungagung-1759568491408_169.jpeg?w=1200
051	sea turtle hatchery sand enclosure Indonesia	partial_hatchery_context_candidate	Indonesia	https://news.detik.com/foto-news/d-8520462/telur-penyu-dipindahkan-ke-penetasan-semi-alami-demi-cegah-perburuan	https://awsimages.detik.net.id/community/media/visual/2026/06/06/pemantauan-penyu-bertelur-1780726171836_169.jpeg?q=90&w=700
052	sea turtle hatchery sand enclosure Indonesia	partial_hatchery_context_candidate	Indonesia	https://regional.espos.id/satwa-langka-pantai-alami-abrasi-jumlah-sarang-telur-penyu-menurun-723900	https://imgcdn.espos.id/%40espos/images/2015/08/070815-Harian-Jogja-Penyelamatan-Penyu-004.jpg?quality=60
053	sea turtle hatchery sand enclosure Benin	partial_hatchery_context_candidate	Benin	https://www.dw.com/en/turtles-find-friends-in-benin/video-64727600	https://static.dw.com/image/64728052_605.jpg
054	sea turtle hatchery sand enclosure Kenya	partial_hatchery_context_candidate	Kenya	https://almanararesort.com/turtle-watch/	https://almanararesort.com/wp-content/uploads/IMG_1306-1.jpg
055	sea turtle hatchery sand enclosure United States	partial_hatchery_context_candidate	United States	https://simplylivingnc.com/sea-turtle-loggerhead-hatchlings-nests-in-north-carolina/	https://simplylivingnc.com/wp-content/uploads/2018/02/0297-18-2015-SEA-TURTLESSSP_6655.jpg
056	sea turtle hatchery sand enclosure Mexico	hatchery_sand_bed_candidate	Mexico	https://www.sabermas.umich.mx/archivo/articulos/526-numero-59/1027-nidos-de-tortuga-marina-por-que-controlar-su-temperatura.html?componentStyle=blog_3&print=1&tmpl=component	https://www.sabermas.umich.mx/images/stories/59/ARTICULO9B.png
057	sea turtle hatchery sand enclosure Cabo Verde	hatchery_sand_bed_candidate	Cabo Verde	https://www.capeandislands.org/local-news/2024-10-29/cape-cod-and-cabo-verde-are-building-scientific-parnt	https://npr.brightspotcdn.com/dims4/default/2bdb412/2147483647/strip/true/crop/1920x1183%2B0%2B129/resize/880x542%21/quality/90/?url=http%3A%2F%2Fnpr-brightspot.s3.amazonaws.com%2Fc9%2Fb8%2F23684d8d451ea13bb2d0211f3110%2Fhatchery.jpg
058	sea turtle hatchery sand enclosure Panama	partial_hatchery_context_candidate	Panama	https://www.ultimahora.com/liberan-280-bebes-de-tortuga-lora-especie-vulnerable-en-una-playa-de-panama	https://grupovierci.brightspotcdn.com/dims4/default/34a7a0e/2147483647/strip/true/crop/5472x3081%2B0%2B275/resize/2000x1126%21/quality/90/?url=https%3A%2F%2Fk2-prod-grupo-vierci.s3.us-east-1.amazonaws.com%2Fbrightspot%2F63%2Fce%2F47ad4a38406f91ca4d868c2b6a75%2Fliberan-280-bebes-de-tortuga-lora-especie-vulnerable-en-una-playa-del-pacifico-de-panama-57078941.jpg
059	sea turtle hatchery sand enclosure Turkey	partial_hatchery_context_candidate	Turkey	https://www.dertourfoundation.co.uk/en/our-projects	https://raisely-images.imgix.net/dertour-uk-foundation/uploads/turkiye-caretta-caretta-bearbeitet-1-jpeg-b04490.jpeg?auto=format&fit=max&q=62&w=1024
060	sea turtle hatchery sand enclosure Mexico	hatchery_sand_bed_candidate	Mexico	https://www.beachpleasemexico.com/es/vallarta-baby-sea-turtle-releases/	https://beachpleasemexico.com/wp-content/uploads/2022/07/Sea-Turtle-Release-Vallarta-1-1024x768.jpeg
EOF
}

extension_for_mime() {
  case "$1" in
    image/jpeg) printf 'jpg' ;;
    image/png) printf 'png' ;;
    image/webp) printf 'webp' ;;
    image/gif) printf 'gif' ;;
    image/heic) printf 'heic' ;;
    *) printf 'img' ;;
  esac
}

while IFS=$'\t' read -r id query rough_role region source_page_url image_url; do
  [[ -n "$id" ]] || continue

  # The first prototype pass is authoritative for URL de-duplication. This
  # keeps this second pool independent even when search ranking changes.
  if [[ -s "$existing_urls_file" ]] && rg -Fqx -- "$image_url" "$existing_urls_file"; then
    continue
  fi
  if [[ -s "$seen_urls_file" ]] && rg -Fqx -- "$image_url" "$seen_urls_file"; then
    continue
  fi
  printf '%s\n' "$image_url" >> "$seen_urls_file"

  existing_file="$(find "$output_dir" -maxdepth 1 -type f -name "${id}.*" -print -quit)"
  if [[ -n "$existing_file" ]]; then
    mime_type="$(file -b --mime-type "$existing_file")"
    local_filename="raw/prototype-web-v2/$(basename "$existing_file")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\tdownloaded\t%s\tcached\t%s\n' \
      "$id" "$query" "$rough_role" "$region" "$source_page_url" "$image_url" "$local_filename" "$mime_type" >> "$results_file"
    continue
  fi

  temporary_file="$(mktemp "$output_dir/.${id}.XXXXXX")"
  http_code="$(curl --location --silent --show-error --connect-timeout 10 --max-time 30 --user-agent "$user_agent" --output "$temporary_file" --write-out '%{http_code}' "$image_url" || true)"
  mime_type="$(file -b --mime-type "$temporary_file" 2>/dev/null || printf 'unknown')"
  byte_count="$(wc -c < "$temporary_file" | tr -d ' ')"

  if [[ "$http_code" =~ ^2[0-9][0-9]$ ]] && [[ "$mime_type" == image/* ]] && [[ "$byte_count" -gt 1024 ]]; then
    extension="$(extension_for_mime "$mime_type")"
    destination="$output_dir/${id}.${extension}"
    mv "$temporary_file" "$destination"
    local_filename="raw/prototype-web-v2/$(basename "$destination")"
    download_status="downloaded"
  else
    rm -f "$temporary_file"
    local_filename=""
    download_status="failed"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$id" "$query" "$rough_role" "$region" "$source_page_url" "$image_url" "$download_status" "$local_filename" "$http_code" "$mime_type" >> "$results_file"

  # A small pause keeps this bounded direct-download pass respectful.
  sleep 0.25
done < <(records)

collected_at="$(date -u +%F)"
tail -n +2 "$results_file" | jq -Rn \
  --arg collected_at "$collected_at" \
  --arg scope "Bounded direct-image download from public pages surfaced by image search. This prototype pool is for local testing only and must not be redistributed or treated as license-cleared training data. Every item is unreviewed; rough_role is a search-time triage hint, not an annotation." \
  --arg source_discovery "Individual image-search results; no category or site crawl. URLs duplicated by training/provenance/prototype-web-images.json are excluded." \
  '
    [inputs
      | split("\t") as $f
      | {
          id: $f[0],
          query: $f[1],
          rough_role: $f[2],
          region: $f[3],
          source_page_url: $f[4],
          image_url: $f[5],
          download_status: $f[6],
          local_filename: (if $f[7] == "" then null else $f[7] end),
          http_code: (if $f[8] == "cached" then $f[8] else ($f[8] | tonumber? // $f[8]) end),
          mime_type: $f[9],
          review_status: "unreviewed",
          usage_restriction: "local_testing_only_not_redistributed"
        }
    ] as $images
    | {
        schema_version: 1,
        collected_at: $collected_at,
        scope: $scope,
        source_discovery: $source_discovery,
        record_count: ($images | length),
        downloaded_count: ($images | map(select(.download_status == "downloaded")) | length),
        failed_count: ($images | map(select(.download_status == "failed")) | length),
        images: $images
      }
  ' > "$json_manifest"

jq -r '
  ["id", "query", "rough_role", "region", "source_page_url", "image_url", "download_status", "local_filename", "http_code", "mime_type", "review_status", "usage_restriction"],
  (.images[] | [
    .id,
    .query,
    .rough_role,
    .region,
    .source_page_url,
    .image_url,
    .download_status,
    .local_filename,
    .http_code,
    .mime_type,
    .review_status,
    .usage_restriction
  ]) | @csv
' "$json_manifest" > "$csv_manifest"

printf 'Wrote %s and %s\n' "$json_manifest" "$csv_manifest"
jq -r '"records=\(.record_count) downloaded=\(.downloaded_count) failed=\(.failed_count)"' "$json_manifest"
