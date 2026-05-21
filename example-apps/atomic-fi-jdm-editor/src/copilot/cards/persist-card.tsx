import React from 'react';
import { PreviewCard, type PreviewCardProps } from './preview-card';

export type PersistCardProps = Omit<PreviewCardProps, 'applyLabel'> & {
  sideEffectLabel: string;
};

export const PersistCard: React.FC<PersistCardProps> = ({ sideEffectLabel, ...rest }) => {
  return <PreviewCard {...rest} applyLabel={sideEffectLabel} />;
};
