const assetRoot = "/images/game"

// Original placeholder art shipped with this project. Keeping every visual in
// one catalog lets later milestones replace renderers or files without changing
// world-state and networking code.
export const graphicsCatalog = Object.freeze({
  version: 1,
  ships: Object.freeze({
    localScout: {src: `${assetRoot}/ships/local-scout.svg`, width: 72, height: 54},
    remoteScout: {src: `${assetRoot}/ships/remote-scout.svg`, width: 66, height: 50},
  }),
  npcs: Object.freeze({
    sentinel: {src: `${assetRoot}/npcs/sentinel.svg`, width: 60, height: 60},
  }),
  lasers: Object.freeze({
    pulse: {src: `${assetRoot}/lasers/pulse.svg`, width: 48, height: 8},
  }),
  explosions: Object.freeze({
    plasma: {src: `${assetRoot}/explosions/plasma.svg`, width: 96, height: 96},
  }),
  drones: Object.freeze({
    scout: {src: `${assetRoot}/drones/scout.svg`, width: 28, height: 22},
  }),
  backgrounds: Object.freeze({
    homeSector: {src: `${assetRoot}/backgrounds/home-sector.svg`, width: 512, height: 512},
  }),
})

export class GraphicsAssets {
  constructor(catalog = graphicsCatalog) {
    this.catalog = catalog
    this.images = new Map()
  }

  preload() {
    for (const [category, entries] of Object.entries(this.catalog)) {
      if (category === "version") continue

      for (const [name, definition] of Object.entries(entries)) {
        const image = new Image()
        image.decoding = "async"
        image.src = definition.src
        image.addEventListener("load", () => this.images.set(`${category}:${name}`, image), {once: true})
      }
    }
  }

  get(category, name) {
    return {
      definition: this.catalog[category]?.[name],
      image: this.images.get(`${category}:${name}`),
    }
  }
}
