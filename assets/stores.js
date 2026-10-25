// Where "Get Shecurity" sends each phone. Fill in APPLE once the App Store listing is live.
var SHECURITY_STORES = {
  play: "https://play.google.com/store/apps/details?id=io.github.punselie15.shecurity",
  apple: "",
  web: "https://shecurity.app/app/"
};
function shecurityPlatform() {
  var ua = navigator.userAgent || "";
  if (/android/i.test(ua)) return "android";
  if (/iphone|ipad|ipod/i.test(ua) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)) return "ios";
  return "desktop";
}
function shecurityStoreLink(p) {
  p = p || shecurityPlatform();
  if (p === "android") return SHECURITY_STORES.play;
  if (p === "ios") return SHECURITY_STORES.apple || SHECURITY_STORES.web;
  return "";
}
// every element with data-get becomes the right link for this phone; on a computer it opens the QR code section
document.addEventListener("DOMContentLoaded", function () {
  var p = shecurityPlatform(), href = shecurityStoreLink(p);
  document.documentElement.setAttribute("data-platform", p);
  Array.prototype.forEach.call(document.querySelectorAll("[data-get]"), function (a) {
    if (href) a.href = href;
    var label = a.querySelector("[data-get-label]");
    if (label && p === "android") label.textContent = "Get it on Google Play";
    if (label && p === "ios") label.textContent = SHECURITY_STORES.apple ? "Download on the App Store" : "Open Shecurity on iPhone";
  });
});
