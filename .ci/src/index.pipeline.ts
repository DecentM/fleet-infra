import './configure'

import * as ConcourseTs from '@decentm/concourse-ts'
import { create_auto_pipeline } from '@decentm/concourse-ts-recipe-auto-pipeline'

import { git_ci } from './resources/git';

const PIPELINE_NAME = 'fleet-infra'

const auto_pipeline = create_auto_pipeline({
  path: `.ci/dist/pipeline/${PIPELINE_NAME}.yml`,
  resource: git_ci,
});

export default () => new ConcourseTs.Pipeline(PIPELINE_NAME, auto_pipeline());
