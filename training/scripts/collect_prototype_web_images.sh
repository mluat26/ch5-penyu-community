#!/usr/bin/env bash
# Collect a bounded, local-only prototype image pool from individual public web
# pages found by image search. It intentionally does not crawl sites or write
# tracked provenance files; successful and failed requests are recorded under
# ignored training/raw/prototype-web/ for later manifest generation.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="$repo_root/training/raw/prototype-web"
result_file="$output_dir/download-results.tsv"
user_agent="community-challenge-prototype-research/1.0 (local testing; contact repository maintainer)"

mkdir -p "$output_dir"

if [[ ! -f "$result_file" ]]; then
  printf 'id\tquery\trough_role\tsource_page_url\timage_url\tdownload_status\tlocal_filename\thttp_code\tmime_type\n' > "$result_file"
fi

records() {
  cat <<'EOF'
001	sea turtle hatchery sand nests Sri Lanka	hatchery_sand_bed_candidate	https://www.bindugopalrao.com/kosgoda-turtle-conservation/	https://www.bindugopalrao.com/wp-content/uploads/2023/05/WhatsApp-Image-2023-05-20-at-11.18.57-1.jpeg
002	sea turtle hatchery sand enclosure netted nests	hatchery_sand_bed_candidate	https://puliharamalaysia.org/chakar-hutan/	https://puliharamalaysia.org/wp-content/uploads/2024/02/Chakar-Hutan_Nests-Saved.webp
003	sea turtle hatchery sand enclosure Cape Verde	hatchery_sand_bed_candidate	https://www.capeandislands.org/local-news/2024-10-29/cape-cod-and-cabo-verde-are-building-scientific-parnt	https://npr.brightspotcdn.com/dims4/default/2bdb412/2147483647/strip/true/crop/1920x1183%2B0%2B129/resize/880x542%21/quality/90/?url=http%3A%2F%2Fnpr-brightspot.s3.amazonaws.com%2Fc9%2Fb8%2F23684d8d451ea13bb2d0211f3110%2Fhatchery.jpg
004	turtle egg hatchery enclosure sand	egg_nest_closeup	https://ameblo.jp/kebin0708/entry-12855021887.html	https://stat.ameba.jp/user_images/20240606/00/kebin0708/4a/3f/j/o2016151215447953395.jpg
005	turtle egg hatchery enclosure sand	hatchery_sand_bed_candidate	https://maleesanat01.github.io/Sea-Turtle-Site/bentotahatchery.html	https://maleesanat01.github.io/Sea-Turtle-Site/turtleimages/ben1.jpg
006	turtle nest corral sea turtle	hatchling_enclosure_context	https://www.mundoporlibre.com/2016	https://1.bp.blogspot.com/-BhRy8spt4C4/VXwjy0O5LXI/AAAAAAAAPFA/_KNFz-ncQkQ/s1600/DSCN1685.JPG
007	turtle egg hatchery enclosure sand	hard_negative_context	https://tortues-terrestres.forumactif.com/t110136-oeuf-de-pelomedusa	https://i.servimg.com/u/f39/17/51/21/38/dsc_0010.jpg
008	sea turtle hatchery sand nests enclosure	hatchery_sand_bed_candidate	https://hetanderebali.nl/turtle-hatchery-project-pemuteran/	https://hetanderebali.nl/wp-content/uploads/Pemuteran-schildpadden-project-8-jpg.webp
009	sea turtle conservation hatchery sand bed	hatchery_sand_bed_candidate	https://www.sabermas.umich.mx/archivo/articulos/526-numero-59/1027-nidos-de-tortuga-marina-por-que-controlar-su-temperatura.html?componentStyle=blog_3&print=1&tmpl=component	https://www.sabermas.umich.mx/images/stories/59/ARTICULO9B.png
010	turtle hatchery enclosure sand	hatchery_sand_bed_candidate	https://asiadivingvacation.com/resort/lankayan-island-dive-resort	https://cdn.asiadivingvacation.com/images/diveresorts/lankayan-island-dive-resort/gallery/simca-turtle-hatchery2.jpg
011	sea turtle hatchery sand pits Sri Lanka	hatchery_sand_bed_candidate	https://maleesanat01.github.io/Sea-Turtle-Site/hikkaduwahatchery.html	https://maleesanat01.github.io/Sea-Turtle-Site/turtleimages/hikz3.jpg
012	turtle egg hatchery	egg_nest_closeup	https://rachelsruminations.com/turtle-sanctuaries-in-malaysia/	https://rachelsruminations.com/wp-content/uploads/2018/09/turtle-eggs.jpg
013	sea turtle hatchery sand enclosure netted nests	hatchery_sand_bed_candidate	https://rachelsruminations.com/turtle-sanctuaries-in-malaysia/	https://rachelsruminations.com/wp-content/uploads/2018/09/hatchery.jpg
014	turtle nest corral conservation sand	nest_corral_candidate	https://cancun.gob.mx/cancun/noticias/leer/1173	https://cancun.gob.mx/uploads/6/32/06%20%28748%29.Jpeg
015	sea turtle hatchery sand enclosure netted nests	hatchery_context	https://www.seaturtlestatus.org/articles/2024/2/13/turning-up-the-heat-on-sea-turtles	https://images.squarespace-cdn.com/content/v1/5b80290bee1759a50e3a86b3/03357642-2b15-4c85-9e52-d0e02548f8b5/Kemp%27sRidleyTurtle_TDR_29May23_4579B_CMYK.jpeg?format=2500w
016	sea turtle hatchery sand enclosure netted nests	hatchling_enclosure_context	https://www.sueddeutsche.de/wissen/gruene-meeresschildkroete-artenschutz-klimawandel-umweltchemikalien-1.6302947	https://www.sueddeutsche.de/2023/11/13/45f1d4b8-e5e7-487c-8d61-abc6fd0c7626.jpeg?fm=jpeg&q=60&rect=0%2C68%2C1200%2C675&width=1000
017	turtle nest corral sea turtle	hatchery_sand_bed_candidate	https://www.vivapuerto.com/vp35/baby-turtle-releases.php	https://www.vivapuerto.com/vp35/images/turtle-camp.jpg
018	sea turtle nest corral conservation sand	nest_corral_candidate	https://www.cancunturtles.com/19-sea-turtle-information?start=5	https://www.cancunturtles.com/images/article-images/the-sea-turtle-protection-corral-30th-of-july-2016-cancun-with-105-nests.jpg
019	sea turtle nest enclosure Florida conservation	nest_corral_candidate	https://www.vistaalmar.es/especies-marinas/general/14172-exito-conservacion-tortugas-marinas-florida-enfrenta-nueva-amenaza.html	https://www.vistaalmar.es/images/ampliadas522/nido-tortuga-enterrado.jpg
020	sea turtle hatchery sand nests Malaysia	hatchery_sand_bed_candidate	https://www.petitgo.com/listing_display?listingid=328	https://petitguru.s3.amazonaws.com/328/5.jpg
021	sea turtle hatchery sand corral Costa Rica	hatchery_context	https://www.volunteerworld.com/en/volunteer-program/turtle-conservation-management-in-costa-rica-manuel-antonio	https://image.volunteerworld.com/9c25fe6da225ce14a348fe8db3f59b3b53dd0405/turtle-centre.jpg?auto=format&fit=crop&h=1170&w=1200
022	sea turtle hatchery sand corral Costa Rica	hatchery_sand_bed_candidate	https://www.ecologyproject.org/post/sea-turtles-in-a-warming-world-how-epi-teaches-climate-change-in-costa-rica	https://static.wixstatic.com/media/9b1cf4_8223f02a509340f9afdc92fe0a7ba4e3~mv2.jpg/v1/fill/w_980%2Ch_654%2Cal_c%2Cq_85%2Cusm_0.66_1.00_0.01%2Cenc_avif%2Cquality_auto/9b1cf4_8223f02a509340f9afdc92fe0a7ba4e3~mv2.jpg
023	sea turtle hatchery sand pen Guatemala	hatchery_activity_context	https://conap.gob.gt/liberacion-de-neonatos-de-tortugas-marinas-y-bienes-y-servicios-que-provee-el-parque-nacional-sipacate-naranjo/	https://conap.gob.gt/wp-content/uploads/2022/10/WhatsApp-Image-2022-10-24-at-3.58.38-PM-2.jpeg
024	sea turtle hatchery sand corral Costa Rica	hatchery_sand_bed_candidate	https://www.workingabroad.com/projects/playa-tortuga-conservation-volunteer-project-costa-rica/gallery/	https://www.workingabroad.com/wp-content/uploads/2018/10/turtle_egg_conservation_costa_rica-scaled-750x500.jpg
025	sea turtle hatchery sand corral Costa Rica	hatchery_structure_context	https://tortugascostarica.org/es/noticias/hemos-construido-un-vivero-ecologico-para-tortugas-marinas-en-costa-rica	https://tortugascostarica.org/images/events/vivero.jpg
026	sea turtle hatchery sand corral Costa Rica	hatchery_sand_bed_candidate	https://laylaslens.com/things-to-do-in-guanacaste/	https://laylaslens.com/wp-content/uploads/2024/11/IMG_4181-1024x934.webp
027	sea turtle hatchery sand corral Costa Rica	hatchery_sand_bed_candidate	https://www.seeturtles.org/turtle-blog/leatherback-hatchlings	https://images.squarespace-cdn.com/content/v1/5369465be4b0507a1fd05af0/1626155813618-NXG7HRBKPNMS7EJMK9UD/IMG_1022.jpeg
028	sea turtle hatchery sand corral Costa Rica	hatchery_context	https://unsplash.com/es/fotos/una-carretilla-azul-llena-de-arena-y-grava-1XJLsq8P-6M	https://images.unsplash.com/photo-1687276702976-32ba3179ccac?auto=format&fit=crop&fm=jpg&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D&ixlib=rb-4.1.0&q=60&w=3000
029	sea turtle hatchery sand corral Costa Rica	hatchling_enclosure_context	https://campamentopalmarito.com/apoyanos/	https://campamentopalmarito.com/wp-content/uploads/2020/04/IMG_2841-768x768.jpg
030	sea turtle hatchery sandy nursery Mexico	nest_corral_candidate	https://beachpleasemexico.com/es/vallarta-baby-sea-turtle-releases/	https://beachpleasemexico.com/wp-content/uploads/2022/07/Sea-Turtle-Release-Vallarta-1-1024x768.jpeg
031	sea turtle hatchery sand corral Costa Rica	hatchery_activity_context	https://savethebluefive.net/formacion/buenas-practicas/conservacion-de-tortugas-marinas-playa-matapalo-carrillo-playa-ostional	https://savethebluefive.net/sites/default/files/styles/imagen_principal_noticias/public/content/images/BP_05_FUNDECODES_Audiovisual_02.JPG?h=2edb67df&itok=1f63Jbvu
032	sea turtle hatchery sand nests Sri Lanka	hatchling_closeup_context	https://travelplanner.lk/day-tours/galle/	https://cdn.travelplanner.lk/round-tours/galle/turtle_hatchery_and_farm.png
033	sea turtle hatchery sand nests Sri Lanka	hatchling_closeup_context	https://www.thegreatprojects.com/projects/the-great-turtle-project	https://cdn.thegreatprojects.com/thegreatprojects/images/f/f/3/5/a/ff35a76cbf7bbefa8d9f767ad48f658e.jpg?format=jpg
034	sea turtle hatchery sand nests Sri Lanka	hatchery_sand_bed_candidate	https://www.outlooktraveller.com/experiences/places-of-interest/world-turtle-day-conservation-project-in-sri-lanka	https://media.assettype.com/outlooktraveller/2024-07/abe5a4f1-0aaf-4743-a930-56ca7a04a34d/tp1%20Our%20Turtle%20Conservation%20Project-facebook.jpg?auto=format%2Ccompress&w=1200
035	sea turtle hatchery sand nests Malaysia	hatchling_closeup_context	https://visitmalaysia.info/kuantan/rimbun-dahan-turtle-hatchery.htm	https://visitmalaysia.info/kuantan/img/rimbun-dahan-hatching.jpg
036	sea turtle hatchery sand nests Sri Lanka	hatchery_sand_bed_candidate	https://podrozowisko.pl/azja/sri-lanka/sri-lanka-wylegarnia-zolwi/	https://podrozowisko.pl/wp-content/uploads/2015/04/Farma-%C5%BC%C3%B3%C5%82wi-w-Kosgoda-2.jpg
037	sea turtle hatchery sand enclosure Turkey	hatchling_closeup_context	https://www.trthaber.com/foto-galeri/hatayda-yesil-deniz-kaplumbagasi-yavrulari-denizle-bulusuyor/73249.html	https://trthaberstatic.cdn.wp.trt.com.tr/resimler/2392000/2392370.jpg
038	sea turtle hatchery sand enclosure Turkey	hatchling_closeup_context	https://www.trthaber.com/foto-galeri/kaplumbaga-yuvalama-alani-25-sahilde-gece-yasagi/58132.html	https://trthaberstatic.cdn.wp.trt.com.tr/resimler/2080000/2081338.jpg
039	sea turtle hatchery sand enclosure Turkey	hatchling_enclosure_context	https://www.blogsicilia.it/agrigento/festa-lampedusa-nati-primi-piccoli-di-tartaruga-caretta-caretta/765526/	https://www.blogsicilia.it/wp-content/uploads/sites/2/2022/08/Tartarughine-1.jpg
040	sea turtle hatchery sand enclosure Cape Verde	hatchery_sand_bed_candidate	https://www.gooverseas.com/volunteer-abroad/cape-verde/program/267663	https://www.gooverseas.com/sites/default/files/styles/1014x/public/image-collections/2021-03-10/hatch5.jpg?itok=HwQbXqRd
041	sea turtle hatchery sand enclosure Turkey	hatchling_enclosure_context	https://www.scrivolibero.it/lampedusa-nati-i-primi-piccoli-di-caretta-caretta/	https://www.scrivolibero.it/wordpress/wp-content/uploads/2022/08/tartaruga.jpg
042	sea turtle hatchery sand enclosure Kenya	hatchling_closeup_context	https://almanararesort.com/turtle-watch/	https://almanararesort.com/wp-content/uploads/IMG_1306-1.jpg
043	sea turtle hatchery sand enclosure Cape Verde	hatchling_enclosure_context	https://juliahammond.blog/2017/12/04/an-interesting-turtle-project-on-sal-cape-verde/	https://juliahammond.blog/wp-content/uploads/2017/12/21743761_1645969415447085_1368305271258042413_o.jpg
044	sea turtle hatchery sand enclosure Cape Verde	nest_corral_candidate	https://www.boavistaofficial.com/explore/natural-reserve-turtle/	https://www.boavistaofficial.com/boa-vista-cabo-verde/wp-content/uploads/2021/04/turtle-nest-reserve-boavista.jpg
045	turtle hatchery sand mesh	nest_corral_candidate	https://kuwaittimes.com/article/41692/health/gabon-battles-for-baby-sea-turtles-survival/	https://kuwaittimes.com/kuwaittimes/uploads/images/2026/03/31/374775.jpg
046	turtle hatchery sand mesh	hatchery_sand_bed_candidate	https://fiaes.org.sv/blog/noticias-4/post/quelonia-conservando-las-tortugas-marinas-235	https://fiaes.org.sv/web/image/21258/2_EIA.jpg?access_token=f3e8ee7a-89d7-48a9-b83d-dfeeb20f1a99
047	turtle hatchery sand mesh	hatchery_sand_bed_candidate	https://oem.com.mx/elsoldeacapulco/local/desamparan-autoridades-a-los-campamentos-tortugueros-guerrero-ayuntamiento-gobierno-ecologia-noticia-17005980	https://oem.com.mx/elsoldeacapulco/img/17058645/1552981215/BASE_LANDSCAPE/1200/image.webp
048	turtle hatchery sand mesh	nest_corral_candidate	https://www.capeverde.co.uk/blog/adopting-a-hatchling	https://assets.serenity.co.uk/51000-51999/51251/720x480.jpg
049	penetasan telur penyu pasir konservasi	hatchery_activity_context	https://news.detik.com/foto-news/d-8144882/potret-relawan-selamatkan-ratusan-telur-penyu-dari-predator-di-tulungagung	https://awsimages.detik.net.id/community/media/visual/2025/10/04/potret-relawan-selamatkan-ratusan-telur-penyu-dari-predator-di-tulungagung-1759568491408_169.jpeg?w=1200
050	penetasan telur penyu pasir konservasi	hatchling_closeup_context	https://www.discoveryterengganu.com/tempat/chagar-hutang-turtle-sanctuary/	https://media.discoveryterengganu.com/wp-content/uploads/2025/03/Chagar-Hutang-Turtle-Sanctuary.webp
051	penetasan telur penyu pasir konservasi	hatchery_activity_context	https://news.detik.com/foto-news/d-8520462/telur-penyu-dipindahkan-ke-penetasan-semi-alami-demi-cegah-perburuan	https://awsimages.detik.net.id/community/media/visual/2026/06/06/pemantauan-penyu-bertelur-1780726171836_169.jpeg?q=90&w=700
052	penetasan telur penyu pasir konservasi	hatchery_context	https://regional.espos.id/satwa-langka-pantai-alami-abrasi-jumlah-sarang-telur-penyu-menurun-723900	https://imgcdn.espos.id/%40espos/images/2015/08/070815-Harian-Jogja-Penyelamatan-Penyu-004.jpg?quality=60
053	penetasan telur penyu pasir konservasi	hatchling_release_context	https://www.antaranews.com/berita/1898820/penampungan-telur-upaya-selamatkan-penyu-dari-kepunahan	https://img.antaranews.com/cache/730x487/2020/12/16/KOMIFoto8.jpg
054	penetasan telur penyu pasir konservasi	egg_nest_closeup	https://sumbar.antaranews.com/berita/270931/penyelamat-telur-penyu-dari-pantai-padang-pariaman	https://cdn.antaranews.com/cache/800x533/2019/06/08/WhatsApp-Image-2019-06-05-at-19.11.21.jpeg
055	penetasan telur penyu pasir konservasi	hatchling_release_context	https://www.antaranews.com/berita/545029/107-telur-penyu-di-pantai-mukomuko-dicuri	https://cdn.antaranews.com/cache/1200x800/2015/09/20150904antarafoto-pelestarian-penyu-030915-fik-5.jpg
056	penetasan telur penyu pasir konservasi	hatchery_activity_context	https://kaltim.idntimes.com/news/kalimantan-timur/nyawa-penyu-diselamatkan-ribuan-telur-ditanam-kembali-di-pasir-paloh-00-stls6-b48xqk	https://image.idntimes.com/post/20250622/upload_59c596e38f358fc457ce628bb05a7fb9_a189abb6-3744-428e-84a7-3ade44c6b898.jpeg
057	penetasan telur penyu pasir konservasi	hatchery_activity_context	https://siej.or.id/id/envirotalk/eliza-marthen-kissya-kearifan-lokal-dianggap-ketinggalan-zaman	https://siej.or.id/sites/default/files/styles/medium/public/articles/Eliza-Haruku-4.png?itok=KvsZx2KK
058	penetasan telur penyu pasir konservasi	egg_nest_closeup	https://kirana-retreat.com/blog/turtle-conservation-in-indonesia/	https://kirana-retreat.com/wp-content/uploads/2023/01/turtleeggs-1.jpeg
059	penetasan telur penyu pasir konservasi	egg_nest_closeup	https://www.dialooghotels.com/hotel/banyuwangi/activity-detail/giant-sea-turtles-at-sukamade	https://www.dialooghotels.com/upload/web/l/wild0472_5hi7p.jpg
060	penetasan telur penyu pasir konservasi	hatchery_context	https://www.jawapos.com/berita-sekitar-anda/01235451/tiga-pantai-tulungagung-jadi-tempat-bertelur-penyu-lengkang-dan-hijau	https://assets.promediateknologi.id/crop/0x0%3A0x0/750x500/webp/photo/jawapos/2019/08/Pantai-tulungagung-telur-penyu.jpg
061	sea turtle egg hatchery mesh sand	egg_nest_closeup	https://www.zubludiving.com/conservation/mabul-turtle-hatchery	https://www.zubludiving.com/images/Conservation-Projects/Turtle-Hatchery/Sabah_Turtle_Nest_Eggs2.jpg
062	sea turtle egg hatchery mesh sand	hatchling_closeup_context	https://zanteturtlecenter.com/en/work-with-us/	https://zanteturtlecenter.com/wp-content/uploads/IMG_2832-min.jpg
063	sea turtle egg hatchery mesh sand	hatchling_closeup_context	https://www.beachjunki.org/sea-turtle-conservation/	https://www.beachjunki.org/wp-content/uploads/2022/02/10868107_302374709972219_5391782034219273081_n.jpg
064	sea turtle egg hatchery mesh sand	hatchling_closeup_context	https://www.lifegate.it/tarta-dogs-cani-addestrati-nidi-tartarughe-marine-caretta-caretta	https://cdn.lifegate.it/uvJgB3p8p9i7AU4M-oSxMPVTRoU%3D/768x/smart/https%3A/www.lifegate.it/app/uploads/2023/09/tartarughe-caretta-caretta.jpg
065	sea turtle egg hatchery mesh sand	hatchling_closeup_context	https://vet-magazin.com/wissenschaft/exoten-medizin/Schildkroeten-Niststrand.html	https://vet-magazin.com/wissenschaft/exoten-medizin/Schildkroeten-Niststrand/img_157977.jpg?v=1468499668&version=full_com
066	sea turtle hatchery staff transfer eggs	hatchery_activity_context	https://www.seaturtlestatus.org/articles/2024/2/13/turning-up-the-heat-on-sea-turtles	https://images.squarespace-cdn.com/content/5369465be4b0507a1fd05af0/f57af9c0-a4f4-4375-842a-9f2cdc894d3b/RG%2Bstaff%2Btransfer%2Beggs%2Bto%2Bhatchery.jpeg?content-type=image%2Fjpeg
EOF
}

extension_for_mime() {
  case "$1" in
    image/jpeg) printf 'jpg' ;;
    image/png) printf 'png' ;;
    image/webp) printf 'webp' ;;
    image/gif) printf 'gif' ;;
    *) printf 'img' ;;
  esac
}

records | while IFS=$'\t' read -r id query rough_role source_page_url image_url; do
  existing_file="$(find "$output_dir" -maxdepth 1 -type f -name "${id}.*" ! -name 'download-results.tsv' -print -quit)"
  if [[ -n "$existing_file" ]]; then
    existing_mime="$(file -b --mime-type "$existing_file")"
    existing_name="raw/prototype-web/$(basename "$existing_file")"
    printf '%s\t%s\t%s\t%s\t%s\tdownloaded\t%s\t%s\t%s\n' \
      "$id" "$query" "$rough_role" "$source_page_url" "$image_url" "$existing_name" "existing" "$existing_mime" >> "$result_file"
    continue
  fi

  temporary_file="$(mktemp "$output_dir/.${id}.XXXXXX")"
  http_code="$(curl --location --silent --show-error --connect-timeout 10 --max-time 30 --user-agent "$user_agent" --output "$temporary_file" --write-out '%{http_code}' "$image_url" || true)"
  mime_type="$(file -b --mime-type "$temporary_file")"
  byte_count="$(wc -c < "$temporary_file" | tr -d ' ')"

  if [[ "$http_code" =~ ^2[0-9][0-9]$ ]] && [[ "$mime_type" == image/* ]] && [[ "$byte_count" -gt 1024 ]]; then
    extension="$(extension_for_mime "$mime_type")"
    destination="$output_dir/${id}.${extension}"
    mv "$temporary_file" "$destination"
    local_filename="raw/prototype-web/$(basename "$destination")"
    download_status="downloaded"
  else
    rm -f "$temporary_file"
    local_filename=""
    download_status="failed"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$id" "$query" "$rough_role" "$source_page_url" "$image_url" "$download_status" "$local_filename" "$http_code" "$mime_type" >> "$result_file"

  # A short per-image pause keeps this bounded direct-download pass respectful.
  sleep 0.45
done
