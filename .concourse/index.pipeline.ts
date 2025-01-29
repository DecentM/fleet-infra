import * as ConcourseTs from '@decentm/concourse-ts'
import { create_auto_pipeline } from '@decentm/concourse-ts-recipe-auto-pipeline'

import { git_ci } from './resources/git';

const auto_pipeline = create_auto_pipeline({
  path: '.ci/pipeline/index.yml',
  resource: git_ci,
});

export default () => new ConcourseTs.Pipeline('index', auto_pipeline(((pipeline)  => {
  pipeline.name = 'index'
})));
