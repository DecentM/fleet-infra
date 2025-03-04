import * as ConcourseTs from '@decentm/concourse-ts'
import * as Git from '@decentm/concourse-ts-resource-git'

const git_type: Git.ResourceType = new ConcourseTs.ResourceType('git', (rt) => {
  rt.set_type('registry-image')

  rt.source = {
    repository: 'concourse/git-resource',
    tag: '1.17.0-20250129',
  }
})

export type GitInput = {
  name: string
  repo: string
  branch: string
  ignore_paths?: string[]
  paths?: string[]
}

const create_git_resource = (input: GitInput): Git.Resource =>
  new ConcourseTs.Resource(input.name, git_type, (r) => {
    r.source = {
      uri: `https://github.com/${input.repo}`,
      branch: input.branch,
      ignore_paths: input.ignore_paths,
      paths: input.paths,
      username: 'DecentM',
    }

    r.icon = 'github'
  })

export const git = create_git_resource({
  branch: 'main',
  repo: 'DecentM/fleet-infra',
  name: 'git',
  ignore_paths: ['ci', '.ci'],
})

export const git_ci = create_git_resource({
  branch: 'main',
  repo: 'DecentM/fleet-infra',
  name: 'git-ci',
  paths: ['ci', '.ci'],
})
