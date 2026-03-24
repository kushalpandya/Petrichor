import { defineConfig } from 'sponsorkit'

export default defineConfig({
  github: {
    login: 'kushalpandya',
    type: 'user',
  },
  outputDir: '../assets',
  formats: ['svg'],
  includePrivate: true,
  includePastSponsors: true,
  async onSponsorsAllFetched(sponsors) {
    // SponsorKit doesn't pass `includePrivate` to the GitHub GraphQL API,
    // so private sponsors are never fetched. Re-query with it enabled.
    const token = process.env.SPONSORKIT_GITHUB_TOKEN
    if (!token) return

    const res = await fetch('https://api.github.com/graphql', {
      method: 'POST',
      headers: {
        Authorization: `bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        query: `{
          user(login: "kushalpandya") {
            sponsorshipsAsMaintainer(includePrivate: true, activeOnly: false, first: 100) {
              nodes {
                privacyLevel
                tier { monthlyPriceInDollars }
                createdAt
                sponsorEntity {
                  ... on User { login name avatarUrl websiteUrl }
                  ... on Organization { login name avatarUrl websiteUrl }
                }
              }
            }
          }
        }`,
      }),
    })

    const data = await res.json()
    const nodes = data.data?.user?.sponsorshipsAsMaintainer?.nodes || []
    const existingLogins = new Set(sponsors.map(s => s.sponsor.login))

    for (const node of nodes) {
      if (node.privacyLevel !== 'PRIVATE') continue
      const login = node.sponsorEntity?.login
      if (!login || existingLogins.has(login)) continue

      sponsors.push({
        sponsor: {
          login,
          name: node.sponsorEntity.name || login,
          avatarUrl: '',
          linkUrl: `https://github.com/${login}`,
          type: 'User',
        },
        monthlyDollars: node.tier?.monthlyPriceInDollars ?? -1,
        privacyLevel: 'PRIVATE',
        createdAt: node.createdAt,
        isOneTime: !node.tier,
        provider: 'github',
      })
    }
  },
  onSvgGenerated(svg) {
    const seen = new Map()
    return svg.replace(
      /(<clipPath id=")([^"]+)("[\s\S]*?clip-path="url\(#)\2(\)")/g,
      (match, p1, id, p3, p4) => {
        const count = seen.get(id) || 0
        seen.set(id, count + 1)
        if (count === 0) return match
        const newId = `${id}_${count}`
        return `${p1}${newId}${p3}${newId}${p4}`
      },
    )
  },
  tiers: [
    {
      preset: {
        avatar: {
          size: 52,
        },
        boxWidth: 72,
        boxHeight: 72,
        container: {
          sidePadding: 30,
        },
      },
    },
  ],
})
